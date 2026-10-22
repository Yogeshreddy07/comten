import 'package:flutter/material.dart';

import '../../core/utils/navigation_guard.dart';

class DeleteDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;

  const DeleteDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Delete',
  });

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Delete',
  }) async {
    if (!context.canPushRoute) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: errorColor),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
