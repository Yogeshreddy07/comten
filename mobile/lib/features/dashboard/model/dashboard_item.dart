import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';

enum DashboardModule {
  projects,
  employees,
  attendance,
  notifications,
  settings,
  teamManagement,
  tasks,
  leave,
  timesheet,
  billing,
  statusUpdate,
  reasonForDelay,
  activities,
  approval,
}

extension DashboardModuleX on DashboardModule {
  String get title {
    switch (this) {
      case DashboardModule.projects:
        return AppStrings.dashboardModuleProjects;
      case DashboardModule.employees:
        return AppStrings.dashboardModuleEmployees;
      case DashboardModule.attendance:
        return AppStrings.dashboardModuleAttendance;
      case DashboardModule.notifications:
        return AppStrings.dashboardModuleNotifications;
      case DashboardModule.settings:
        return AppStrings.dashboardModuleSettings;
      case DashboardModule.teamManagement:
        return AppStrings.dashboardModuleTeamManagement;
      case DashboardModule.tasks:
        return AppStrings.dashboardModuleTasks;
      case DashboardModule.leave:
        return AppStrings.dashboardModuleLeave;
      case DashboardModule.timesheet:
        return AppStrings.dashboardModuleTimesheet;
      case DashboardModule.billing:
        return AppStrings.dashboardModuleBilling;
      case DashboardModule.statusUpdate:
        return AppStrings.dashboardModuleStatusUpdate;
      case DashboardModule.reasonForDelay:
        return AppStrings.dashboardModuleReasonForDelay;
      case DashboardModule.activities:
        return AppStrings.dashboardModuleActivities;
      case DashboardModule.approval:
        return AppStrings.dashboardModuleApproval;
    }
  }

  String get description {
    switch (this) {
      case DashboardModule.projects:
        return AppStrings.dashboardModuleProjectsDescription;
      case DashboardModule.employees:
        return AppStrings.dashboardModuleEmployeesDescription;
      case DashboardModule.attendance:
        return AppStrings.dashboardModuleAttendanceDescription;
      case DashboardModule.notifications:
        return AppStrings.dashboardModuleNotificationsDescription;
      case DashboardModule.settings:
        return AppStrings.dashboardModuleSettingsDescription;
      case DashboardModule.teamManagement:
        return AppStrings.dashboardModuleTeamManagementDescription;
      case DashboardModule.tasks:
        return AppStrings.dashboardModuleTasksDescription;
      case DashboardModule.leave:
        return AppStrings.dashboardModuleLeaveDescription;
      case DashboardModule.timesheet:
        return AppStrings.dashboardModuleTimesheetDescription;
      case DashboardModule.billing:
        return AppStrings.dashboardModuleBillingDescription;
      case DashboardModule.statusUpdate:
        return AppStrings.dashboardModuleStatusUpdateDescription;
      case DashboardModule.reasonForDelay:
        return AppStrings.dashboardModuleReasonForDelayDescription;
      case DashboardModule.activities:
        return AppStrings.dashboardModuleActivitiesDescription;
      case DashboardModule.approval:
        return AppStrings.dashboardModuleApprovalDescription;
    }
  }

  /// Solid icon used on the Quick Access grid/list cards.
  IconData get icon {
    switch (this) {
      case DashboardModule.projects:
        return Icons.folder;
      case DashboardModule.employees:
        return Icons.groups;
      case DashboardModule.attendance:
        return Icons.fact_check;
      case DashboardModule.notifications:
        return Icons.notifications_active;
      case DashboardModule.settings:
        return Icons.settings;
      case DashboardModule.teamManagement:
        return Icons.manage_accounts;
      case DashboardModule.tasks:
        return Icons.task_alt;
      case DashboardModule.leave:
        return Icons.event_busy;
      case DashboardModule.timesheet:
        return Icons.schedule;
      case DashboardModule.billing:
        return Icons.receipt_long;
      case DashboardModule.statusUpdate:
        return Icons.published_with_changes;
      case DashboardModule.reasonForDelay:
        return Icons.report_problem;
      case DashboardModule.activities:
        return Icons.checklist;
      case DashboardModule.approval:
        return Icons.fact_check;
    }
  }

  /// Outlined icon used on the bottom navigation bar - deliberately distinct
  /// from [icon] to match the Captain Dashboard's existing visual style.
  IconData get outlinedIcon {
    switch (this) {
      case DashboardModule.projects:
        return Icons.folder_copy_outlined;
      case DashboardModule.employees:
        return Icons.groups_outlined;
      case DashboardModule.attendance:
        return Icons.fact_check_outlined;
      case DashboardModule.notifications:
        return Icons.notifications_outlined;
      case DashboardModule.settings:
        return Icons.settings_outlined;
      case DashboardModule.teamManagement:
        return Icons.manage_accounts_outlined;
      case DashboardModule.tasks:
        return Icons.task_alt_outlined;
      case DashboardModule.leave:
        return Icons.event_busy_outlined;
      case DashboardModule.timesheet:
        return Icons.schedule_outlined;
      case DashboardModule.billing:
        return Icons.receipt_long_outlined;
      case DashboardModule.statusUpdate:
        return Icons.published_with_changes_outlined;
      case DashboardModule.reasonForDelay:
        return Icons.report_problem_outlined;
      case DashboardModule.activities:
        return Icons.checklist_outlined;
      case DashboardModule.approval:
        return Icons.fact_check_outlined;
    }
  }

  Color get accentColor {
    switch (this) {
      case DashboardModule.projects:
        return AppColors.moduleProjects;
      case DashboardModule.employees:
        return AppColors.moduleEmployees;
      case DashboardModule.attendance:
        return AppColors.moduleAttendance;
      case DashboardModule.notifications:
        return AppColors.moduleNotifications;
      case DashboardModule.settings:
        return AppColors.moduleSettings;
      case DashboardModule.teamManagement:
        return AppColors.moduleTeamManagement;
      case DashboardModule.tasks:
        return AppColors.moduleTasks;
      case DashboardModule.leave:
        return AppColors.moduleLeave;
      case DashboardModule.timesheet:
        return AppColors.moduleTimesheet;
      case DashboardModule.billing:
        return AppColors.moduleBilling;
      case DashboardModule.statusUpdate:
        return AppColors.moduleStatusUpdate;
      case DashboardModule.reasonForDelay:
        return AppColors.moduleReasonForDelay;
      case DashboardModule.activities:
        return AppColors.moduleActivities;
      case DashboardModule.approval:
        return AppColors.moduleApproval;
    }
  }
}

/// A [DashboardModule] paired with optional role-specific label overrides -
/// e.g. the Team Leader dashboard shows the [DashboardModule.projects] card
/// as "Assigned Projects" while the Employee dashboard shows the same
/// module as "My Projects", without duplicating the module's identity
/// (icon/accent/navigation target).
class DashboardModuleEntry {
  final DashboardModule module;
  final String? titleOverride;
  final String? descriptionOverride;

  const DashboardModuleEntry(
    this.module, {
    this.titleOverride,
    this.descriptionOverride,
  });

  String get title => titleOverride ?? module.title;
  String get description => descriptionOverride ?? module.description;
}

/// Single source of truth for "which Quick Access modules does this role
/// see" - adding a future role only means adding one case here.
extension DashboardRoleModulesX on UserRole {
  List<DashboardModuleEntry> get dashboardModules {
    switch (this) {
      case UserRole.captain:
        return const [
          DashboardModuleEntry(DashboardModule.projects),
          DashboardModuleEntry(
            DashboardModule.employees,
            titleOverride: AppStrings.dashboardModuleProjectControllers,
            descriptionOverride:
                AppStrings.dashboardModuleProjectControllersDescription,
          ),
          DashboardModuleEntry(DashboardModule.billing),
          DashboardModuleEntry(DashboardModule.approval),
          DashboardModuleEntry(DashboardModule.notifications),
          DashboardModuleEntry(DashboardModule.settings),
        ];
      case UserRole.projectManager:
        return const [
          DashboardModuleEntry(DashboardModule.projects),
          DashboardModuleEntry(DashboardModule.employees),
          DashboardModuleEntry(DashboardModule.billing),
          DashboardModuleEntry(DashboardModule.activities),
          DashboardModuleEntry(DashboardModule.notifications),
          DashboardModuleEntry(DashboardModule.settings),
        ];
      case UserRole.teamLeader:
        return const [
          DashboardModuleEntry(DashboardModule.attendance),
          DashboardModuleEntry(
            DashboardModule.timesheet,
            titleOverride: AppStrings.dashboardModuleTimesheetApprovals,
            descriptionOverride:
                AppStrings.dashboardModuleTimesheetApprovalsDescription,
          ),
          DashboardModuleEntry(
            DashboardModule.projects,
            titleOverride: AppStrings.dashboardModuleProjectDatabase,
            descriptionOverride: AppStrings.dashboardModuleProjectDatabaseDescription,
          ),
          DashboardModuleEntry(DashboardModule.statusUpdate),
          DashboardModuleEntry(DashboardModule.reasonForDelay),
          DashboardModuleEntry(DashboardModule.notifications),
          DashboardModuleEntry(DashboardModule.settings),
        ];
      case UserRole.employee:
        return const [
          DashboardModuleEntry(
            DashboardModule.projects,
            titleOverride: AppStrings.dashboardModuleMyProjects,
            descriptionOverride: AppStrings.dashboardModuleMyProjectsDescription,
          ),
          DashboardModuleEntry(DashboardModule.attendance),
          DashboardModuleEntry(DashboardModule.timesheet),
          DashboardModuleEntry(DashboardModule.notifications),
          DashboardModuleEntry(DashboardModule.settings),
        ];
    }
  }
}
