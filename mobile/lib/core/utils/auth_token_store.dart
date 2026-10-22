import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Credentials use the existing platform secure-storage backend, never Hive.
/// Operations are serialized so startup migration cannot race logout.
class AuthTokenStore {
  AuthTokenStore(this.preferences, {FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final SharedPreferences preferences;
  final FlutterSecureStorage storage;
  final Set<String> _unreadable = {};
  Future<void> _pending = Future<void>.value();
  static bool isCredential(String key) =>
      key.startsWith('jwt_token_') || key.startsWith('fcm_token_');
  String _secureKey(String key) => 'auth_v1_$key';

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object error) {});
    return result;
  }

  Future<void> migrateLegacy() => _serial(() async {
    for (final key in preferences.getKeys().where(isCredential).toList()) {
      try {
        final existing = await storage.read(key: _secureKey(key));
        final legacy = preferences.getString(key);
        if (existing == null && legacy != null && legacy.isNotEmpty) {
          await storage.write(key: _secureKey(key), value: legacy);
          if (await storage.read(key: _secureKey(key)) != legacy) {
            throw StateError('Secure credential storage unavailable');
          }
        }
      } catch (_) {
        // Fail closed; never fall back to the plaintext credential.
        _unreadable.add(key);
        try {
          await storage.delete(key: _secureKey(key));
        } catch (_) {}
      } finally {
        if (!await preferences.remove(key)) {
          _unreadable.add(key);
          throw StateError('Legacy credential cleanup failed');
        }
      }
    }
  });

  Future<String?> read(String key) => _serial(() async {
    if (_unreadable.contains(key)) return null;
    try {
      return await storage.read(key: _secureKey(key));
    } catch (_) {
      _unreadable.add(key);
      try {
        await storage.delete(key: _secureKey(key));
      } catch (_) {}
      return null;
    }
  });

  Future<void> write(String key, String value) => _serial(() async {
    await storage.write(key: _secureKey(key), value: value);
    _unreadable.remove(key);
    await preferences.remove(key);
  });

  Future<void> clear(String employeeCode) => _serial(() async {
    Object? failure;
    for (final key in ['jwt_token_$employeeCode', 'fcm_token_$employeeCode']) {
      _unreadable.add(key);
      try {
        await storage.delete(key: _secureKey(key));
      } catch (error) {
        failure = error;
      }
      await preferences.remove(key);
    }
    if (failure != null) throw StateError('Secure session cleanup failed');
  });
}
