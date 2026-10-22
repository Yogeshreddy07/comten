import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Encrypted, account-isolated snapshots. Expired authorization never permits an offline reopen.
class AccountCache {
  static final AccountCache instance = AccountCache();
  final _storage = const FlutterSecureStorage();
  Box<String>? _box;
  String? _uid;
  int? _version;
  DateTime? _lease;
  Future<void> bind(String uid, int version, {bool renew=true}) async {
    if (_uid != uid || _version != version) {
      await _box?.close();
      _box = null;
      final name = 'snapshots_v1_${uid}_$version';
      var key = await _storage.read(key: 'hive_$uid');
      try {if(key!=null && base64Url.decode(key).length!=32) key=null;}catch(_) {key=null;}
      if (key == null) {
        key = base64UrlEncode(Hive.generateSecureKey());
        await _storage.write(key: 'hive_$uid', value: key);
      }
      try {
        _box = await Hive.openBox<String>(name, encryptionCipher: HiveAesCipher(base64Url.decode(key)));
      } catch (_) {
        await Hive.deleteBoxFromDisk(name);
        _box = await Hive.openBox<String>(name, encryptionCipher: HiveAesCipher(base64Url.decode(key)));
      }
      _uid = uid; _version = version;
    }
    if(renew) {
      _lease = DateTime.now().add(const Duration(minutes: 15));
      await _storage.write(key:'cache_scope_$uid',value:jsonEncode({'version':version,'lease':_lease!.millisecondsSinceEpoch}));
    }
  }
  Future<Map<String,dynamic>?> restoreProfile(String uid) async {
    try {
      final meta=jsonDecode(await _storage.read(key:'cache_scope_$uid')??'null');
      if(meta==null||meta['lease']<DateTime.now().millisecondsSinceEpoch) return null;
      await bind(uid,meta['version'] as int,renew:false);
      _lease=DateTime.fromMillisecondsSinceEpoch(meta['lease'] as int);
      final data=read('auth_profile');
      return data is Map ? Map<String,dynamic>.from(data) : null;
    } catch(_) { return null; }
  }
  Future<void> put(String key, dynamic value) async {
    await _box?.put(key, jsonEncode({'schema':1,'created':DateTime.now().millisecondsSinceEpoch,'expires':DateTime.now().add(const Duration(minutes:15)).millisecondsSinceEpoch,'data':value}));
  }
  dynamic read(String key,{bool stale=true}) {
    if (_lease == null || DateTime.now().isAfter(_lease!)) return null;
    try {
      final row=jsonDecode(_box?.get(key) ?? 'null');
      if(row == null || row['schema']!=1 || row['expires']<DateTime.now().millisecondsSinceEpoch) return null;
      if(!stale && (row['created']??0)<DateTime.now().subtract(const Duration(seconds:60)).millisecondsSinceEpoch) return null;
      return row['data'];
    } catch (_) { return null; }
  }
  Future<void> invalidateData() async {
    final profile=_box?.get('auth_profile');
    await _box?.clear();
    if(profile!=null) await _box?.put('auth_profile',profile);
  }
  Future<void> close() async {
    await _box?.close();_box=null;_uid=null;_version=null;_lease=null;
  }
  Future<void> clear({String? accountUid}) async {
    final uid=accountUid??_uid;
    await _box?.clear(); await _box?.close(); _box=null;
    if(uid != null) await _storage.delete(key:'hive_$uid');
    if(uid != null) await _storage.delete(key:'cache_scope_$uid');
    _uid=null; _version=null; _lease=null;
  }
}
