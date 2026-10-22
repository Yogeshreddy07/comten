import 'package:flutter/material.dart';

import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';
import '../../dashboard/model/dashboard_item.dart';

const _illustrationsDir = 'assets/illustrations';

/// One icon+text bullet shown under a [WalkthroughPage]'s title.
class WalkthroughHighlight {
  final IconData icon;
  final String text;

  const WalkthroughHighlight({required this.icon, required this.text});
}

/// A single page of the first-login walkthrough: a title, exactly 2 short
/// highlight bullets, and a bottom-half SVG illustration (see
/// `assets/illustrations/`).
class WalkthroughPage {
  final String title;
  final List<WalkthroughHighlight> highlights;
  final String illustrationAsset;

  const WalkthroughPage({
    required this.title,
    required this.highlights,
    required this.illustrationAsset,
  });
}

/// Highlight copy + illustration for one [DashboardModule] - shared across
/// every role whose dashboard includes that module, so the copy is authored
/// once per module rather than once per role.
class _ModuleWalkthroughContent {
  final List<WalkthroughHighlight> highlights;
  final String illustrationAsset;

  const _ModuleWalkthroughContent({
    required this.highlights,
    required this.illustrationAsset,
  });
}

/// [role] drives the handful of modules whose walkthrough content genuinely
/// differs depending on who's looking at it - e.g. the Captain's "Project
/// Controller Management" tile is the same [DashboardModule.employees]
/// module as every other role's "Employee Management" tile, but describes
/// managing Project Controllers rather than employees. Everywhere else, the
/// same copy is shared across every role that has the module.
_ModuleWalkthroughContent _contentFor(DashboardModule module, UserRole role) {
  switch (module) {
    case DashboardModule.projects:
      // Employee-only: "My Projects" is about accessing your own assigned
      // work, not the shared "track overall progress" framing below.
      return role == UserRole.employee
          ? const _ModuleWalkthroughContent(
              highlights: [
                WalkthroughHighlight(
                  icon: Icons.visibility_outlined,
                  text: AppStrings.walkthroughMyProjectsHighlight1,
                ),
                WalkthroughHighlight(
                  icon: Icons.assignment_outlined,
                  text: AppStrings.walkthroughMyProjectsHighlight2,
                ),
              ],
              illustrationAsset: '$_illustrationsDir/projects.svg',
            )
          : const _ModuleWalkthroughContent(
              highlights: [
                WalkthroughHighlight(
                  icon: Icons.visibility_outlined,
                  text: AppStrings.walkthroughProjectsHighlight1,
                ),
                WalkthroughHighlight(
                  icon: Icons.groups_outlined,
                  text: AppStrings.walkthroughProjectsHighlight2,
                ),
              ],
              illustrationAsset: '$_illustrationsDir/projects.svg',
            );
    case DashboardModule.attendance:
      // Team Leader-only: this role only monitors attendance - Employees
      // are the ones who check in/out (see the shared copy below).
      return role == UserRole.teamLeader
          ? const _ModuleWalkthroughContent(
              highlights: [
                WalkthroughHighlight(
                  icon: Icons.groups_outlined,
                  text: AppStrings.walkthroughAttendanceTeamLeaderHighlight1,
                ),
                WalkthroughHighlight(
                  icon: Icons.insert_chart_outlined_rounded,
                  text: AppStrings.walkthroughAttendanceTeamLeaderHighlight2,
                ),
              ],
              illustrationAsset: '$_illustrationsDir/attendance.svg',
            )
          : const _ModuleWalkthroughContent(
              highlights: [
                WalkthroughHighlight(
                  icon: Icons.fingerprint,
                  text: AppStrings.walkthroughAttendanceHighlight1,
                ),
                WalkthroughHighlight(
                  icon: Icons.insert_chart_outlined_rounded,
                  text: AppStrings.walkthroughAttendanceHighlight2,
                ),
              ],
              illustrationAsset: '$_illustrationsDir/attendance.svg',
            );
    case DashboardModule.timesheet:
      // Employee-only: submitting a timesheet, not the Team Leader's
      // approval-queue framing below.
      return role == UserRole.employee
          ? const _ModuleWalkthroughContent(
              highlights: [
                WalkthroughHighlight(
                  icon: Icons.schedule_outlined,
                  text: AppStrings.walkthroughTimesheetSubmitHighlight1,
                ),
                WalkthroughHighlight(
                  icon: Icons.fact_check_outlined,
                  text: AppStrings.walkthroughTimesheetSubmitHighlight2,
                ),
              ],
              illustrationAsset: '$_illustrationsDir/timesheet.svg',
            )
          : const _ModuleWalkthroughContent(
              highlights: [
                WalkthroughHighlight(
                  icon: Icons.schedule_outlined,
                  text: AppStrings.walkthroughTimesheetHighlight1,
                ),
                WalkthroughHighlight(
                  icon: Icons.fact_check_outlined,
                  text: AppStrings.walkthroughTimesheetHighlight2,
                ),
              ],
              illustrationAsset: '$_illustrationsDir/timesheet.svg',
            );
    case DashboardModule.employees:
      return role == UserRole.captain
          ? const _ModuleWalkthroughContent(
              highlights: [
                WalkthroughHighlight(
                  icon: Icons.groups_outlined,
                  text: AppStrings.walkthroughProjectControllerHighlight1,
                ),
                WalkthroughHighlight(
                  icon: Icons.admin_panel_settings_outlined,
                  text: AppStrings.walkthroughProjectControllerHighlight2,
                ),
              ],
              illustrationAsset: '$_illustrationsDir/project_controller.svg',
            )
          : const _ModuleWalkthroughContent(
              highlights: [
                WalkthroughHighlight(
                  icon: Icons.groups_outlined,
                  text: AppStrings.walkthroughEmployeeManagementHighlight1,
                ),
                WalkthroughHighlight(
                  icon: Icons.manage_accounts_outlined,
                  text: AppStrings.walkthroughEmployeeManagementHighlight2,
                ),
              ],
              illustrationAsset: '$_illustrationsDir/employee_management.svg',
            );
    case DashboardModule.billing:
      // Captain-only: views billing status but never edits it, unlike the
      // Project Controller's copy below (walkthroughBillingHighlight2).
      return role == UserRole.captain
          ? const _ModuleWalkthroughContent(
              highlights: [
                WalkthroughHighlight(
                  icon: Icons.receipt_long_outlined,
                  text: AppStrings.walkthroughBillingHighlight1,
                ),
                WalkthroughHighlight(
                  icon: Icons.price_change_outlined,
                  text: AppStrings.walkthroughBillingCaptainHighlight2,
                ),
              ],
              illustrationAsset: '$_illustrationsDir/billing.svg',
            )
          : const _ModuleWalkthroughContent(
              highlights: [
                WalkthroughHighlight(
                  icon: Icons.receipt_long_outlined,
                  text: AppStrings.walkthroughBillingHighlight1,
                ),
                WalkthroughHighlight(
                  icon: Icons.price_change_outlined,
                  text: AppStrings.walkthroughBillingHighlight2,
                ),
              ],
              illustrationAsset: '$_illustrationsDir/billing.svg',
            );
    case DashboardModule.statusUpdate:
      // Team Leader only (see _extraWalkthroughModules) - submits a status
      // update for Project Controller approval.
      return const _ModuleWalkthroughContent(
        highlights: [
          WalkthroughHighlight(
            icon: Icons.edit_note_outlined,
            text: AppStrings.walkthroughStatusUpdateHighlight1,
          ),
          WalkthroughHighlight(
            icon: Icons.fact_check_outlined,
            text: AppStrings.walkthroughStatusUpdateHighlight2,
          ),
        ],
        illustrationAsset: '$_illustrationsDir/status_update.svg',
      );
    case DashboardModule.reasonForDelay:
      // Team Leader only (see _extraWalkthroughModules) - submits a delay
      // request for Project Controller review.
      return const _ModuleWalkthroughContent(
        highlights: [
          WalkthroughHighlight(
            icon: Icons.report_problem_outlined,
            text: AppStrings.walkthroughReasonForDelayHighlight1,
          ),
          WalkthroughHighlight(
            icon: Icons.rate_review_outlined,
            text: AppStrings.walkthroughReasonForDelayHighlight2,
          ),
        ],
        illustrationAsset: '$_illustrationsDir/delay_reason.svg',
      );
    case DashboardModule.activities:
      return const _ModuleWalkthroughContent(
        highlights: [
          WalkthroughHighlight(
            icon: Icons.playlist_add_check_outlined,
            text: AppStrings.walkthroughActivitiesHighlight1,
          ),
          WalkthroughHighlight(
            icon: Icons.checklist_outlined,
            text: AppStrings.walkthroughActivitiesHighlight2,
          ),
        ],
        illustrationAsset: '$_illustrationsDir/activities.svg',
      );
    case DashboardModule.approval:
      return const _ModuleWalkthroughContent(
        highlights: [
          WalkthroughHighlight(
            icon: Icons.fact_check_outlined,
            text: AppStrings.walkthroughApprovalHighlight1,
          ),
          WalkthroughHighlight(
            icon: Icons.thumb_up_alt_outlined,
            text: AppStrings.walkthroughApprovalHighlight2,
          ),
        ],
        illustrationAsset: '$_illustrationsDir/approval.svg',
      );
    case DashboardModule.notifications:
    case DashboardModule.settings:
    case DashboardModule.teamManagement:
    case DashboardModule.tasks:
    case DashboardModule.leave:
      throw UnsupportedError(
        'No walkthrough content authored for $module - it is never part of '
        'a role\'s walkthroughPages selection below.',
      );
  }
}

/// Single source of truth for "what does this role's first-login tour
/// show". Built from each role's real [dashboardModules] (see
/// `dashboard_item.dart`) instead of duplicating that copy - a future role
/// or module change only needs updating in one place to be reflected here
/// too. [_walkthroughModuleCount] caps how many of those modules (in their
/// existing order) get a page, skipping low-priority ones like
/// Notifications/Settings; [_extraWalkthroughModules] covers modules that
/// deserve a walkthrough page but aren't part of a role's Quick Access grid
/// at all (none currently need this - Status Update/Reason for Delay are
/// Team Leader-only and already appear via their own dashboardModules).
extension RoleWalkthroughContentX on UserRole {
  int get _walkthroughModuleCount {
    switch (this) {
      case UserRole.captain:
        return 4; // Projects, Project Controller Management, Billing, Approval
      case UserRole.projectManager:
        return 4; // Projects, Employee Management, Billing, Activities
      case UserRole.teamLeader:
        return 5; // Attendance, Timesheet Approvals, Projects, Status Update, Reason for Delay
      case UserRole.employee:
        return 3; // My Projects, Attendance, Timesheets
    }
  }

  List<DashboardModuleEntry> get _extraWalkthroughModules {
    switch (this) {
      case UserRole.captain:
      case UserRole.projectManager:
      case UserRole.teamLeader:
      case UserRole.employee:
        return const [];
    }
  }

  WalkthroughPage _pageFor(DashboardModuleEntry entry) {
    final content = _contentFor(entry.module, this);
    return WalkthroughPage(
      title: entry.title,
      highlights: content.highlights,
      illustrationAsset: content.illustrationAsset,
    );
  }

  List<WalkthroughPage> get walkthroughPages {
    final moduleEntries = [
      ...dashboardModules.take(_walkthroughModuleCount),
      ..._extraWalkthroughModules,
    ];

    return [
      WalkthroughPage(
        title: AppStrings.walkthroughWelcomeTitle(displayLabel),
        highlights: const [
          WalkthroughHighlight(
            icon: Icons.dashboard_customize_outlined,
            text: AppStrings.walkthroughWelcomeHighlight1,
          ),
          WalkthroughHighlight(
            icon: Icons.bolt_outlined,
            text: AppStrings.walkthroughWelcomeHighlight2,
          ),
        ],
        illustrationAsset: '$_illustrationsDir/welcome.svg',
      ),
      for (final entry in moduleEntries) _pageFor(entry),
      const WalkthroughPage(
        title: AppStrings.walkthroughGetStartedTitle,
        highlights: [
          WalkthroughHighlight(
            icon: Icons.check_circle_outline,
            text: AppStrings.walkthroughGetStartedHighlight1,
          ),
          WalkthroughHighlight(
            icon: Icons.rocket_launch_outlined,
            text: AppStrings.walkthroughGetStartedHighlight2,
          ),
        ],
        illustrationAsset: '$_illustrationsDir/all_set.svg',
      ),
    ];
  }
}
