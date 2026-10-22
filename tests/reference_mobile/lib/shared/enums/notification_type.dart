import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Mirrors the backend's `com.comten.enums.NotificationType` exactly -
/// values are sent/received as these upper-snake-case names.
enum NotificationType {
  timesheetSubmitted,
  timesheetApproved,
  timesheetRejected,
  projectCreated,
  projectUpdated,
  delayRequested,
  projectSubmittedForBilling,
  projectChangeRequested,
  projectChangeApproved,
  projectChangeRejected,
  projectDeadlineExtended,
  billingReversionRequested,
  billingReversionApproved,
  billingReversionRejected,
  lowHoursRemaining,
  moduleMilestoneReached,
  projectMilestoneReached,
  checkoutReminder,
  timesheetReminder,
  unknown,
}

extension NotificationTypeX on NotificationType {
  IconData get icon {
    switch (this) {
      case NotificationType.timesheetSubmitted:
        return Icons.schedule_outlined;
      case NotificationType.timesheetApproved:
        return Icons.check_circle_outline;
      case NotificationType.timesheetRejected:
        return Icons.cancel_outlined;
      case NotificationType.projectCreated:
        return Icons.create_new_folder_outlined;
      case NotificationType.projectUpdated:
        return Icons.folder_outlined;
      case NotificationType.delayRequested:
        return Icons.report_problem_outlined;
      case NotificationType.projectSubmittedForBilling:
        return Icons.receipt_long_outlined;
      case NotificationType.projectChangeRequested:
        return Icons.fact_check_outlined;
      case NotificationType.projectChangeApproved:
        return Icons.check_circle_outline;
      case NotificationType.projectChangeRejected:
        return Icons.cancel_outlined;
      case NotificationType.projectDeadlineExtended:
        return Icons.event_available_outlined;
      case NotificationType.billingReversionRequested:
        return Icons.fact_check_outlined;
      case NotificationType.billingReversionApproved:
        return Icons.check_circle_outline;
      case NotificationType.billingReversionRejected:
        return Icons.cancel_outlined;
      case NotificationType.lowHoursRemaining:
        return Icons.hourglass_bottom_outlined;
      case NotificationType.moduleMilestoneReached:
        return Icons.timeline_outlined;
      case NotificationType.projectMilestoneReached:
        return Icons.flag_outlined;
      case NotificationType.checkoutReminder:
        return Icons.logout_outlined;
      case NotificationType.timesheetReminder:
        return Icons.pending_actions_outlined;
      case NotificationType.unknown:
        return Icons.notifications_outlined;
    }
  }

  Color get color {
    switch (this) {
      case NotificationType.timesheetSubmitted:
        return AppColors.moduleTimesheet;
      case NotificationType.timesheetApproved:
        return AppColors.statusActive;
      case NotificationType.timesheetRejected:
        return AppColors.statusCancelled;
      case NotificationType.projectCreated:
      case NotificationType.projectUpdated:
        return AppColors.moduleProjects;
      case NotificationType.delayRequested:
        return AppColors.statusOnHold;
      case NotificationType.projectSubmittedForBilling:
        return AppColors.moduleBilling;
      case NotificationType.projectChangeRequested:
        return AppColors.moduleApproval;
      case NotificationType.projectChangeApproved:
        return AppColors.statusActive;
      case NotificationType.projectChangeRejected:
        return AppColors.statusCancelled;
      case NotificationType.projectDeadlineExtended:
        return AppColors.moduleProjects;
      case NotificationType.billingReversionRequested:
        return AppColors.moduleApproval;
      case NotificationType.billingReversionApproved:
        return AppColors.statusActive;
      case NotificationType.billingReversionRejected:
        return AppColors.statusCancelled;
      case NotificationType.lowHoursRemaining:
        return AppColors.statusOnHold;
      case NotificationType.moduleMilestoneReached:
        return AppColors.moduleStatusUpdate;
      case NotificationType.projectMilestoneReached:
        return AppColors.moduleProjects;
      case NotificationType.checkoutReminder:
        return AppColors.moduleAttendance;
      case NotificationType.timesheetReminder:
        return AppColors.moduleTimesheet;
      case NotificationType.unknown:
        return AppColors.textSecondary;
    }
  }

  /// For [NotificationType.moduleMilestoneReached], the alert color follows
  /// the crossed threshold per the Milestone Alert Levels spec - green at
  /// 30%, yellow at 60%, red at 90% - instead of the fixed [color] every
  /// other notification type uses. Falls back to [color] otherwise (wrong
  /// type, or [milestonePercent] not yet known).
  Color alertColor(int? milestonePercent) {
    if (this == NotificationType.moduleMilestoneReached && milestonePercent != null) {
      if (milestonePercent >= 90) return AppColors.statusCancelled;
      if (milestonePercent >= 60) return AppColors.statusOnHold;
      if (milestonePercent >= 30) return AppColors.statusActive;
    }
    return color;
  }

  bool get isDelayRequest =>
      this == NotificationType.delayRequested;

  /// Whether tapping this notification should deep-link into the Approval
  /// module's request detail (see [NotificationItem.changeRequestId]).
  bool get isChangeRequest =>
      this == NotificationType.projectChangeRequested ||
      this == NotificationType.projectChangeApproved ||
      this == NotificationType.projectChangeRejected;

  /// Whether tapping this notification should deep-link into
  /// [BillingApprovalDetailsScreen] for the specific request (see
  /// [NotificationItem.billingChangeRequestId]) - mirrors [isChangeRequest]
  /// but for billing status reversion requests, which carry a separate id
  /// and lead to a different detail screen.
  bool get isBillingReversion =>
      this == NotificationType.billingReversionRequested ||
      this == NotificationType.billingReversionApproved ||
      this == NotificationType.billingReversionRejected;

  static NotificationType fromApiValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'TIMESHEET_SUBMITTED':
        return NotificationType.timesheetSubmitted;
      case 'TIMESHEET_APPROVED':
        return NotificationType.timesheetApproved;
      case 'TIMESHEET_REJECTED':
        return NotificationType.timesheetRejected;
      case 'PROJECT_CREATED':
        return NotificationType.projectCreated;
      case 'PROJECT_UPDATED':
        return NotificationType.projectUpdated;
      case 'DELAY_REQUESTED':
        return NotificationType.delayRequested;
      case 'PROJECT_SUBMITTED_FOR_BILLING':
        return NotificationType.projectSubmittedForBilling;
      case 'PROJECT_CHANGE_REQUESTED':
        return NotificationType.projectChangeRequested;
      case 'PROJECT_CHANGE_APPROVED':
        return NotificationType.projectChangeApproved;
      case 'PROJECT_CHANGE_REJECTED':
        return NotificationType.projectChangeRejected;
      case 'PROJECT_DEADLINE_EXTENDED':
        return NotificationType.projectDeadlineExtended;
      case 'BILLING_REVERSION_REQUESTED':
        return NotificationType.billingReversionRequested;
      case 'BILLING_REVERSION_APPROVED':
        return NotificationType.billingReversionApproved;
      case 'BILLING_REVERSION_REJECTED':
        return NotificationType.billingReversionRejected;
      case 'LOW_HOURS_REMAINING':
        return NotificationType.lowHoursRemaining;
      case 'MODULE_MILESTONE_REACHED':
        return NotificationType.moduleMilestoneReached;
      case 'PROJECT_MILESTONE_REACHED':
        return NotificationType.projectMilestoneReached;
      case 'CHECKOUT_REMINDER':
        return NotificationType.checkoutReminder;
      case 'TIMESHEET_REMINDER':
        return NotificationType.timesheetReminder;
      default:
        return NotificationType.unknown;
    }
  }
}
