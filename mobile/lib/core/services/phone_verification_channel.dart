import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../constant/api_constants.dart';

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
  final _events = StreamController<PhoneVerificationEvent>.broadcast();
  Stream<PhoneVerificationEvent> get events => _events.stream;
  Future<Map<String,dynamic>> _call(String path,Map<String,dynamic> body) async {
    final token=await FirebaseAuth.instance.currentUser?.getIdToken();
    if(token==null) throw const PhoneVerificationException('Sign in to activate your enrolled phone.');
    final result=await http.post(Uri.parse('${ApiConstants.baseUrl}$path'),headers:{'Content-Type':'application/json','Authorization':'Bearer $token'},body:jsonEncode(body));
    final data=jsonDecode(result.body) as Map<String,dynamic>;
    if(result.statusCode!=200) throw PhoneVerificationException(data['message']?.toString()??'Verification failed');
    return Map<String,dynamic>.from(data['data'] as Map? ?? {});
  }
  Future<void> startVerification(String phoneNumber) async {
    try {
      await _call('/auth/phone/send',{'phone':phoneNumber});
      _events.add(PhoneCodeSent('msg91-enrolled-phone'));
    } on PhoneVerificationException catch(e) { _events.add(PhoneVerificationFailed(e.message)); rethrow; }
  }
  Future<void> resendCode(String phoneNumber) => startVerification(phoneNumber);
  Future<String> submitCode({required String verificationId,required String code}) async {
    final result=await _call('/auth/phone/verify',{'otp':code});
    if(result['customToken'] is String) await FirebaseAuth.instance.signInWithCustomToken(result['customToken'] as String);
    final token=await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if(token==null) throw const PhoneVerificationException('Verification session ended');
    return token;
  }
}
