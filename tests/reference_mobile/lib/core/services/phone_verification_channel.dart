import 'package:flutter/services.dart';

/// A state change emitted by the native Firebase Auth phone sign-in flow while it's in
/// progress - see [PhoneVerificationChannel.events].
sealed class PhoneVerificationEvent {}

/// An SMS with a code was sent; the caller should now collect the code from the user and
/// call [PhoneVerificationChannel.submitCode] with this [verificationId].
class PhoneCodeSent extends PhoneVerificationEvent {
  final String verificationId;
  PhoneCodeSent(this.verificationId);
}

/// The device verified the code itself (SMS auto-retrieval or instant verification) before
/// the user typed anything - [idToken] is already the final Firebase Auth ID token, ready to
/// send straight to the backend.
class PhoneAutoVerified extends PhoneVerificationEvent {
  final String idToken;
  PhoneAutoVerified(this.idToken);
}

class PhoneVerificationFailed extends PhoneVerificationEvent {
  final String message;
  PhoneVerificationFailed(this.message);
}

class PhoneVerificationException implements Exception {
  final String message;

  const PhoneVerificationException(this.message);

  @override
  String toString() => message;
}

/// Dart-side bridge to the native Android Firebase Auth phone sign-in integration
/// (frontend/android/app/.../MainActivity.kt) - the callback-driven verification flow has no
/// Flutter plugin of its own, so this talks to a hand-rolled MethodChannel + EventChannel pair
/// instead.
class PhoneVerificationChannel {
  static const _methodChannel = MethodChannel('com.comten.app/phone_verification');
  static const _eventChannel = EventChannel('com.comten.app/phone_verification_events');

  /// Native verification state changes (code sent, auto-verified, or failed) for whichever
  /// [startVerification]/[resendCode] call is currently in flight.
  Stream<PhoneVerificationEvent> get events => _eventChannel.receiveBroadcastStream().map((
    event,
  ) {
    final map = Map<Object?, Object?>.from(event as Map);
    switch (map['type']) {
      case 'codeSent':
        return PhoneCodeSent(map['verificationId'] as String);
      case 'autoVerified':
        return PhoneAutoVerified(map['idToken'] as String);
      case 'failed':
      default:
        return PhoneVerificationFailed(map['message'] as String? ?? 'Verification failed');
    }
  });

  /// Triggers Firebase to send an SMS code to [phoneNumber] (E.164 format). Outcomes arrive on
  /// [events], not as a return value.
  Future<void> startVerification(String phoneNumber) async {
    try {
      await _methodChannel.invokeMethod('startVerification', {'phoneNumber': phoneNumber});
    } on PlatformException catch (e) {
      throw PhoneVerificationException(e.message ?? 'Failed to start phone verification.');
    }
  }

  /// Re-sends the SMS code to the same number verification was last started for.
  Future<void> resendCode(String phoneNumber) async {
    try {
      await _methodChannel.invokeMethod('resendCode', {'phoneNumber': phoneNumber});
    } on PlatformException catch (e) {
      throw PhoneVerificationException(e.message ?? 'Failed to resend verification code.');
    }
  }

  /// Submits the user-entered [code] for the verification identified by [verificationId] (from
  /// a [PhoneCodeSent] event) and returns the resulting Firebase Auth ID token.
  Future<String> submitCode({required String verificationId, required String code}) async {
    try {
      final raw = await _methodChannel.invokeMethod<Map<Object?, Object?>>('submitCode', {
        'verificationId': verificationId,
        'code': code,
      });
      final idToken = raw?['idToken'] as String?;
      if (idToken == null) {
        throw const PhoneVerificationException(
          'Phone verification did not return a result. Please try again.',
        );
      }
      return idToken;
    } on PlatformException catch (e) {
      throw PhoneVerificationException(e.message ?? 'Incorrect code. Please try again.');
    }
  }
}
