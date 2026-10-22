import 'package:local_auth/local_auth.dart';

enum BiometricResult {
  success,
  hardwareUnavailable,
  notEnrolled,
  failed,
}

class BiometricHelper {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isHardwareAvailable() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return isSupported && canCheck;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> isFingerprintEnrolled() async {
    try {
      final availableBiometrics = await _auth.getAvailableBiometrics();
      return availableBiometrics.contains(BiometricType.fingerprint) ||
          availableBiometrics.contains(BiometricType.strong) ||
          availableBiometrics.contains(BiometricType.face);
    } catch (e) {
      return false;
    }
  }

  static Future<BiometricResult> authenticate({
    String reason = 'Scan your fingerprint to authenticate',
  }) async {
    try {
      final hasHardware = await isHardwareAvailable();
      if (!hasHardware) {
        return BiometricResult.hardwareUnavailable;
      }

      final hasEnrolled = await isFingerprintEnrolled();
      if (!hasEnrolled) {
        return BiometricResult.notEnrolled;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      return authenticated ? BiometricResult.success : BiometricResult.failed;
    } catch (e) {
      return BiometricResult.failed;
    }
  }
}
