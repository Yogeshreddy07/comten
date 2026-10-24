/// Single-use email OTP proof carried from verification to password setup.
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
