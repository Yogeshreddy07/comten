import 'package:flutter/material.dart';

import '../../../shared/widgets/app_button.dart';

/// Thin auth-module wrapper around the shared [AppButton] - kept so existing
/// auth screens don't need call-site changes, while the actual button
/// rendering lives in one place instead of being duplicated.
class AuthButton extends StatelessWidget {
  final String text;
  final bool isLoading;
  final VoidCallback? onPressed;

  const AuthButton({
    super.key,
    required this.text,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      text: text,
      isLoading: isLoading,
      onPressed: onPressed,
    );
  }
}
