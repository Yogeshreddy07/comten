import 'package:flutter/material.dart';

/// Guards against a rapid double-tap opening the same destination twice -
/// whether that's a pushed screen, a dialog, a bottom sheet, or a menu.
///
/// `Navigator.push` (and `showDialog`/`showModalBottomSheet`/`showMenu`,
/// which push a route under the hood) marks the *previous* top route as no
/// longer current synchronously, as soon as the new route is inserted into
/// the navigator's history - well before its entrance animation starts.
/// Checking [canPushRoute] immediately before opening another route means
/// the second tap of a double-tap (or a rapid succession of taps on the
/// same control) sees its own trigger's route already on top and bails out,
/// without needing a per-screen busy flag.
extension NavigationGuard on BuildContext {
  bool get canPushRoute => ModalRoute.of(this)?.isCurrent ?? true;
}
