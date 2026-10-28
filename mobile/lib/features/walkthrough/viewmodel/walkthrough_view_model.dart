import '../../../core/services/performance_trace.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/preference_util.dart';
import '../../../shared/enums/user_role.dart';
import '../model/walkthrough_step.dart';
import '../utils/walkthrough_content.dart';

/// Owns the walkthrough's page state (current page, PageController) and
/// persisting completion. Scoped to a single [WalkthroughScreen] instance
/// (not provided app-wide) - nothing else needs this state.
class WalkthroughViewModel extends PerformanceNotifier {
  final String employeeCode;
  final List<WalkthroughStep> steps;
  final PageController pageController = PageController();

  WalkthroughViewModel({required UserRole role, required this.employeeCode})
      : steps = buildWalkthroughSteps(role);

  int _currentPage = 0;
  int get currentPage => _currentPage;

  bool get isFirstPage => _currentPage == 0;
  bool get isLastPage => _currentPage == steps.length - 1;

  void onPageChanged(int page) {
    _currentPage = page;
    notifyListeners();
  }

  void goNext() {
    if (isLastPage) return;
    pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void goBack() {
    if (isFirstPage) return;
    pageController.previousPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  /// Marks the walkthrough seen for this employee - called by both Skip and
  /// Get Started, since either action means "don't show this again" (see
  /// `PreferenceUtil.setWalkthroughSeen`'s doc comment for why logout does
  /// NOT clear this flag).
  Future<void> markSeen() => PreferenceUtil.setWalkthroughSeen(employeeCode, true);

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }
}
