import 'package:flutter/material.dart';

import '../../core/utils/navigation_guard.dart';
import '../constants/app_strings.dart';

/// Prompts for a rejection reason (required by the backend's
/// `RejectWorkLogRequest`) before a Captain / Project Controller rejects a
/// timesheet entry. Returns the trimmed reason, or `null` if cancelled.
class RejectTimesheetDialog extends StatefulWidget {
  const RejectTimesheetDialog({super.key});

  static Future<String?> show(BuildContext context) {
    if (!context.canPushRoute) return Future.value();
    return showDialog<String>(
      context: context,
      builder: (_) => const RejectTimesheetDialog(),
    );
  }

  @override
  State<RejectTimesheetDialog> createState() => _RejectTimesheetDialogState();
}

class _RejectTimesheetDialogState extends State<RejectTimesheetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(AppStrings.timesheetRejectDialogTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(AppStrings.timesheetRejectDialogMessage),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: AppStrings.timesheetRejectReasonHint,
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? AppStrings.timesheetRejectReasonRequired
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          style: TextButton.styleFrom(foregroundColor: errorColor),
          child: const Text(AppStrings.timesheetRejectButton),
        ),
      ],
    );
  }
}
