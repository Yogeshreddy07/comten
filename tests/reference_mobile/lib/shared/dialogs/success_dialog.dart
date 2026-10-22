import 'package:flutter/material.dart';

import '../../core/utils/navigation_guard.dart';

/// Centered confirmation with a single acknowledgement action - used where a
/// snackbar isn't attention-grabbing enough and the user should explicitly
/// confirm they've seen the result (e.g. after deleting a project/module)
/// before continuing.
class SuccessDialog extends StatelessWidget {
  final String title;
  final String message;
  final String actionLabel;

  const SuccessDialog({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel = 'OK',
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String actionLabel = 'OK',
  }) async {
    if (!context.canPushRoute) return;
    await showDialog<void>(
      context: context,
      builder: (_) => SuccessDialog(
        title: title,
        message: message,
        actionLabel: actionLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Icon(Icons.check_circle_outline, color: colorScheme.primary, size: 32),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(actionLabel),
        ),
      ],
    );
  }
}
