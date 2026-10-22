import 'package:flutter/material.dart';

/// Hides any in-flight snackbar the instant the route changes, so a
/// success/error/info message triggered on one screen can never bleed into
/// the next one. Flutter's `SnackBar` is presented by the single
/// `ScaffoldMessenger` `MaterialApp` installs above the whole `Navigator`,
/// so without this it stays visible across a push/pop - registered as one
/// of `MaterialApp.navigatorObservers` in main.dart.
class SnackbarDismissingObserver extends NavigatorObserver {
  void _dismiss() {
    final context = navigator?.context;
    if (context == null) return;
    // `clearSnackBars` (not `removeCurrentSnackBar`) - a screen that fired
    // several messages in quick succession queues them in the
    // `ScaffoldMessenger`, and only removing the one currently on screen
    // would leave the rest to play out one-by-one on top of whatever screen
    // the user navigated to next.
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _dismiss();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _dismiss();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _dismiss();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _dismiss();
}

class SnackbarUtil {
  SnackbarUtil._();

  /// Every success/error/info message across the app stays visible for this
  /// long before auto-dismissing - long enough to actually read (login
  /// messages, API success/failure responses, validation errors, action
  /// confirmations all route through this one util, so changing it here
  /// changes it everywhere at once).
  static const Duration messageDuration = Duration(seconds: 5);

  static void showSuccess(
      BuildContext context,
      String message,
      ) {
    showSuccessOn(ScaffoldMessenger.of(context), message);
  }

  static void showError(
      BuildContext context,
      String message,
      ) {
    showErrorOn(ScaffoldMessenger.of(context), message);
  }

  /// Same as [showSuccess], but takes an already-resolved
  /// [ScaffoldMessengerState] instead of a [BuildContext] - use when the
  /// message is shown after an `await` (e.g. a confirm dialog + API call):
  /// resolve the messenger with `ScaffoldMessenger.of(context)` *before*
  /// that `await`, since the item-level `context` a list row/menu action
  /// captures can go stale by the time the action finishes (e.g. the list
  /// re-sorts after a `notifyListeners()` mid-await), silently swallowing
  /// the snackbar even though the action itself succeeded.
  static void showSuccessOn(
      ScaffoldMessengerState messenger,
      String message,
      ) {
    // `clearSnackBars` (not `hideCurrentSnackBar`) - drops anything already
    // queued behind the current one too, so a caller that (by a bug, or a
    // rapid repeated tap slipping past its own guard) fires this more than
    // once for the same action never backs up a chain of duplicate
    // messages that would otherwise play out one after another.
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: messageDuration,
        ),
      );
  }

  /// See [showSuccessOn].
  static void showErrorOn(
      ScaffoldMessengerState messenger,
      String message,
      ) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: messageDuration,
        ),
      );
  }

  static void showInfo(
      BuildContext context,
      String message,
      ) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
          duration: messageDuration,
        ),
      );
  }
}