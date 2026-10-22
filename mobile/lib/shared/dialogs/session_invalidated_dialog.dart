import 'package:flutter/material.dart';

import '../../core/utils/navigation_guard.dart';
import '../../core/utils/snackbar_util.dart';

/// Centered modal shown when this device's session was superseded by a
/// newer login elsewhere (see `SessionManager.handleSessionInvalidated`) -
/// deliberately more attention-grabbing than a bottom snackbar for a
/// security-relevant event the user shouldn't be able to miss. By the time
/// this is shown, the logout/redirect to [LoginScreen] has already
/// happened; this is purely informational, so it carries no actions of its
/// own - tapping outside dismisses it, and (matching how long the snackbar
/// it replaces used to stay up) it also dismisses itself automatically.
class SessionInvalidatedDialog extends StatefulWidget {
  final String message;

  const SessionInvalidatedDialog({super.key, required this.message});

  static Future<void> show(BuildContext context, String message) {
    if (!context.canPushRoute) return Future.value();
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SessionInvalidatedDialog(message: message),
    );
  }

  @override
  State<SessionInvalidatedDialog> createState() =>
      _SessionInvalidatedDialogState();
}

class _SessionInvalidatedDialogState extends State<SessionInvalidatedDialog> {
  @override
  void initState() {
    super.initState();
    Future.delayed(SnackbarUtil.messageDuration, () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Icon(Icons.info_outline, color: colorScheme.error, size: 32),
      title: const Text('Signed Out'),
      content: Text(widget.message, textAlign: TextAlign.center),
    );
  }
}
