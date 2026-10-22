import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Only injected by the synthetic Phase 2 harness. Product DI leaves this null.
/// Freshness (10s) and access lease (30s) are fixture values, not business policy.
class ProjectCacheReply {
  final int status;
  final dynamic payload;
  final Map<String, dynamic> metadata;
  const ProjectCacheReply(this.status, this.payload, this.metadata);
}

class ProjectCacheException implements Exception {
  final int status;
  final String message;
  const ProjectCacheException(this.status, this.message);
}

typedef ProjectReadLoader =
    Future<ProjectCacheReply> Function(String key, String? etag, bool force);

String _canonical(dynamic value) {
  dynamic sort(dynamic x) {
    if (x is Map) {
      final keys = x.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: sort(x[k])};
    }
    if (x is List) return x.map(sort).toList();
    return x;
  }

  return jsonEncode(sort(value));
}

bool _validProjectPayload(String key, dynamic payload) {
  bool identity(dynamic row) =>
      row is Map &&
      row['id'] is int &&
      row['projectCode'] is String &&
      row['projectName'] is String &&
      row['status'] is String &&
      row['isActive'] is bool;
  if (key.startsWith('list:')) {
    return payload is List &&
        payload.every((row) => identity(row) && row['moduleCount'] is int);
  }
  return payload is Map &&
      identity(payload) &&
      payload['modules'] is List &&
      (payload['modules'] as List).every(
        (row) =>
            row is Map &&
            row['id'] is int &&
            row['moduleName'] is String &&
            row['status'] is String,
      );
}

bool _validContext(Map context) =>
    context['environment'] == 'synthetic-phase2' &&
    context['uid'] is String &&
    (context['uid'] as String).isNotEmpty &&
    context['session'] is String &&
    (context['session'] as String).isNotEmpty &&
    const [
      'CAPTAIN',
      'PROJECT_CONTROLLER',
      'TEAM_LEADER',
      'EMPLOYEE',
    ].contains(context['role']) &&
    context['authVersion'] is int &&
    context['authVersion'] > 0 &&
    context['accessVersion'] is int &&
    context['accessVersion'] > 0;

class ProjectReadCache extends ChangeNotifier {
  final Box box;
  final ProjectReadLoader loader;
  final DateTime Function() clock;
  Map<String, dynamic>? _context;
  int accessUntil;
  bool online = true;
  bool locked = false;
  int generation = 0;
  int requests = 0;
  int hits = 0;
  Future<void>? _logoutFuture;
  Timer? _leaseTimer;
  final bool _realClock;
  final Map<String, Future<dynamic>> _inflight = {};
  ProjectReadCache(
    this.box,
    this.loader,
    Map<String, dynamic> context,
    this.accessUntil, {
    DateTime Function()? now,
  }) : _context = Map.of(context),
       clock = now ?? DateTime.now,
       _realClock = now == null {
    if (!_validContext(context)) {
      throw ArgumentError('Phase 2 permits only synthetic project data');
    }
    _scheduleExpiry();
  }
  void _scheduleExpiry() {
    _leaseTimer?.cancel();
    if (_realClock && !locked) {
      _leaseTimer = Timer(
        Duration(milliseconds: max(0, accessUntil - now)),
        notifyListeners,
      );
    }
  }

  int get now => clock().millisecondsSinceEpoch;
  bool get authorized => !locked && _context != null && now < accessUntil;
  Map<String, dynamic>? get context =>
      _context == null ? null : Map.of(_context!);
  String scoped(String key) => _canonical([_context, key]);
  static String listKey({bool? active, bool? inProgress}) =>
      'list:active=${active ?? 'any'}:inProgress=${inProgress ?? 'any'}';
  Map<String, dynamic>? _entry(String key) {
    if (!authorized) return null;
    try {
      final raw = box.get(scoped(key));
      if (raw is! String) return null;
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      if (entry['schema'] != 2 ||
          entry['key'] != key ||
          entry['complete'] != true ||
          _canonical(entry['context']) != _canonical(_context) ||
          entry['accessUntil'] is! int ||
          entry['freshUntil'] is! int ||
          entry['storedAt'] is! int ||
          now < entry['storedAt'] ||
          now >= entry['accessUntil'] ||
          entry['etag'] is! String ||
          !_validProjectPayload(key, entry['payload'])) {
        return null;
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  dynamic peek(String key) => _entry(key)?['payload'];
  Future<dynamic> read(String key, {bool force = false}) async {
    if (locked || _context == null) {
      throw const ProjectCacheException(401, 'Project session ended');
    }
    final entry = _entry(key);
    if (!force && entry != null && now < entry['freshUntil']) {
      hits++;
      return entry['payload'];
    }
    if (!online) {
      if (entry != null) {
        hits++;
        return entry['payload'];
      }
      throw const ProjectCacheException(
        0,
        'No authorized offline project data',
      );
    }
    final scopedKey = scoped(key);
    return _inflight.putIfAbsent(
      scopedKey,
      () => _load(key, entry, force).whenComplete(() {
        _inflight.remove(scopedKey);
      }),
    );
  }

  Future<dynamic> _load(
    String key,
    Map<String, dynamic>? previous,
    bool force,
  ) async {
    final start = generation;
    requests++;
    try {
      final reply = await loader(key, previous?['etag'] as String?, force);
      if (start != generation || locked || _context == null) {
        throw const ProjectCacheException(401, 'Project session changed');
      }
      if (reply.status == 401 || reply.status == 403) {
        await logout();
        throw ProjectCacheException(reply.status, 'Project access denied');
      }
      if (reply.status == 404) {
        await box.delete(scoped(key));
        throw const ProjectCacheException(404, 'Project not found');
      }
      if (reply.status != 200 && reply.status != 304) {
        throw ProjectCacheException(reply.status, 'Project refresh failed');
      }
      final meta = Map<String, dynamic>.from(reply.metadata);
      final incoming = Map<String, dynamic>.from(meta['context'] as Map);
      if (!_validContext(incoming) ||
          incoming['uid'] != _context!['uid'] ||
          incoming['session'] != _context!['session'] ||
          meta['schema'] != 2 ||
          meta['key'] != key ||
          meta['complete'] != true ||
          meta['accessUntil'] is! int ||
          meta['freshUntil'] is! int ||
          meta['accessUntil'] <= now ||
          meta['freshUntil'] > meta['accessUntil'] ||
          meta['etag'] is! String) {
        await logout();
        throw const ProjectCacheException(403, 'Invalid project cache scope');
      }
      final sameContext = _canonical(incoming) == _canonical(_context);
      if (reply.status == 304 &&
          (previous == null ||
              !sameContext ||
              meta['etag'] != previous['etag'])) {
        throw const ProjectCacheException(
          503,
          'Invalid conditional project response',
        );
      }
      final payload = reply.status == 304
          ? previous!['payload']
          : reply.payload;
      if (!_validProjectPayload(key, payload)) {
        throw const ProjectCacheException(503, 'Invalid project payload');
      }
      if (!sameContext) {
        await box.clear();
        if (start != generation || locked) {
          throw const ProjectCacheException(401, 'Project session changed');
        }
        generation++;
        _context = incoming;
        notifyListeners();
      }
      accessUntil = meta['accessUntil'];
      _scheduleExpiry();
      final writeGeneration = generation;
      await box.put(
        scoped(key),
        jsonEncode({...meta, 'storedAt': now, 'payload': payload}),
      );
      await box.flush();
      if (!authorized || writeGeneration != generation) {
        // A concurrent logout must not leave a newly persisted late response.
        await box.clear();
        throw const ProjectCacheException(401, 'Project session changed');
      }
      return payload;
    } on ProjectCacheException catch (e) {
      if (e.status == 0 || e.status >= 500) {
        final retained = _entry(key);
        if (retained != null) return retained['payload'];
      }
      rethrow;
    } catch (_) {
      final retained = _entry(key);
      if (retained != null && start == generation) return retained['payload'];
      throw const ProjectCacheException(0, 'Unable to refresh projects');
    }
  }

  Future<void> invalidate() async {
    generation++;
    await box.clear();
    await box.flush();
  }

  Future<void> logout() {
    if (_logoutFuture != null) return _logoutFuture!;
    locked = true;
    _context = null;
    generation++;
    _leaseTimer?.cancel();
    notifyListeners();
    return _logoutFuture = () async {
      await box.clear();
      await box.flush();
    }();
  }

  @override
  void dispose() {
    _leaseTimer?.cancel();
    super.dispose();
  }
}

/// Random per-user key in OS secure storage. Actual Android keystore/backup/upgrade
/// validation is a release gate; VM tests do not establish device protection.
Future<Box> openSyntheticProjectBox(
  String directory,
  String immutableUserId,
  FlutterSecureStorage secureStorage,
) async {
  final namespace = utf8
      .encode(immutableUserId)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final keyName = 'phase2_project_key_$namespace';
  final saved = await secureStorage.read(key: keyName);
  final key = saved == null
      ? List<int>.generate(32, (_) => Random.secure().nextInt(256))
      : base64Decode(saved);
  if (key.length != 32) throw StateError('Invalid project encryption key');
  if (saved == null) {
    await secureStorage.write(key: keyName, value: base64Encode(key));
  }
  return Hive.openBox(
    'phase2_projects_$namespace',
    path: directory,
    encryptionCipher: HiveAesCipher(key),
  );
}
