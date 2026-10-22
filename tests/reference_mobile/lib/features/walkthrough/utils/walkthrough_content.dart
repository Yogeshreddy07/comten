import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';
import '../../dashboard/model/dashboard_item.dart';
import '../model/walkthrough_step.dart';

/// Role-specific "What You Can Do" highlights - the only hand-authored copy
/// this feature needs. Everything else is built from data that already
/// exists (`UserRole.dashboardModules`), so the walkthrough can't drift out
/// of sync with what a role's dashboard actually shows.
const Map<UserRole, List<String>> _roleActionHighlights = {
  UserRole.captain: [
    'View every project and Project Controller',
    'Manage billing across all projects',
    'Approve submitted works from the Approvals page',
    'Review and decide on submitted change requests',
  ],
  UserRole.projectManager: [
    'Create projects together with their first module',
    'Assign Team Leaders and team members to modules',
    'Manage billing and update billing status across modules',
  ],
  UserRole.teamLeader: [
    'Submit status updates for your modules',
    'Submit reasons for delay to Project Controllers',
    'Approve or reject employee timesheets',
  ],
  UserRole.employee: [
    'Submit your timesheet by logging hours against a module',
    'Check in and out for attendance',
    'Track the projects you are assigned to',
  ],
};

/// Builds the fixed 4-page walkthrough for [role]: Welcome, Your Dashboard
/// (from the role's real dashboard tiles), What You Can Do (hand-authored
/// highlights above), Get Started. A standalone pure function - kept out of
/// the ViewModel so content stays trivially testable and the ViewModel stays
/// free of copy-authoring concerns.
List<WalkthroughStep> buildWalkthroughSteps(UserRole role) {
  return [
    WalkthroughStep(
      icon: Icons.waving_hand_rounded,
      title: AppStrings.walkthroughWelcomeTitle(role.displayLabel),
      subtitle: AppStrings.walkthroughWelcomeSubtitle,
      accentColor: AppColors.primary,
    ),
    WalkthroughStep(
      icon: Icons.dashboard_customize_outlined,
      title: AppStrings.walkthroughDashboardPageTitle,
      subtitle: AppStrings.walkthroughDashboardPageSubtitle,
      accentColor: AppColors.moduleProjects,
      highlights: role.dashboardModules
          .map((entry) => WalkthroughHighlight(
                icon: entry.module.icon,
                label: entry.title,
              ))
          .toList(),
    ),
    WalkthroughStep(
      icon: Icons.bolt_outlined,
      title: AppStrings.walkthroughActionsPageTitle,
      subtitle: AppStrings.walkthroughActionsPageSubtitle,
      accentColor: AppColors.moduleStatusUpdate,
      highlights: (_roleActionHighlights[role] ?? const [])
          .map((label) => WalkthroughHighlight(
                icon: Icons.check_circle_outline,
                label: label,
              ))
          .toList(),
    ),
    WalkthroughStep(
      icon: Icons.rocket_launch_outlined,
      title: AppStrings.walkthroughGetStartedTitle,
      subtitle: AppStrings.walkthroughGetStartedSubtitle,
      accentColor: AppColors.statusActive,
    ),
  ];
}
