class ResetPasswordSession {
  final String resetToken;

  ResetPasswordSession({
    required this.resetToken,
  });

  factory ResetPasswordSession.fromJson(
      Map<String, dynamic> json,
      ) {
    return ResetPasswordSession(
      resetToken: json["resetToken"] ?? "",
    );
  }
}