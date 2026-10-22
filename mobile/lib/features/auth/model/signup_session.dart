/// State carried across the multi-step signup flow (verify temp password ->
/// phone OTP -> set password).
///
/// [signupToken] is the single-use proof, issued by
/// `/auth/signup/verify-temp-password`, that this user supplied the correct
/// temporary password. `/auth/signup/set-password` rejects the request without
/// it, so it has to survive every step in between.
class SignupSession {
  final String employeeCode;
  final String signupToken;

  const SignupSession({
    required this.employeeCode,
    required this.signupToken,
  });

  factory SignupSession.fromJson(Map<String, dynamic> json) {
    return SignupSession(
      employeeCode: json['employeeCode'] ?? '',
      signupToken: json['signupToken'] ?? '',
    );
  }
}
