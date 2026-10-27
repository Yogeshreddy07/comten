import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../shared/enums/notification_type.dart';
import '../../approvals/model/project_change_request.dart';
import '../../approvals/view/approval_details_screen.dart';
import '../../approvals/view/approval_list_screen.dart';
import '../../attendance/view/attendance_screen.dart';
import '../../billing/model/billing_entry.dart';
import '../../billing/model/billing_status_change_request.dart';
import '../../billing/view/billing_approval_details_screen.dart';
import '../../billing/view/billing_list_screen.dart';
import '../../billing/view/update_billing_status_screen.dart';
import '../../modules/view/module_details_screen.dart';
import '../../projects/view/project_details_screen.dart';
import '../../worklogs/view/timesheet_approval_list_screen.dart';
import '../../worklogs/view/timesheet_list_screen.dart';
import '../model/notification_item.dart';
import '../view/billing_submitted_details_screen.dart';
import '../view/delay_request_details_screen.dart';
import '../view/notification_list_screen.dart';
import '../viewmodel/notification_view_model.dart';

/// Single source of truth for "which screen does tapping a notification
/// open" - shared by both the in-app Notifications list
/// ([NotificationListScreen]) and Home Screen push notification taps (see
/// `PushNotificationService`), so the two stay in sync automatically.
class NotificationNavigator {
  NotificationNavigator._();

  /// "Open" a notification the way any tap on a [NotificationItem] should
  /// behave, wherever it's tapped from: mark it read, then either drill into
  /// [DelayRequestDetailsScreen] (delay requests carry Approve/Reject
  /// actions a Project Controller needs) or fall through to [openFor] for
  /// everything else. Shared by [NotificationListScreen] and the unread
  /// notifications gate shown before the dashboard so both stay in sync.
  static Future<void> openNotification(
    BuildContext context,
    NotificationItem notification,
    NotificationViewModel viewModel,
  ) async {
    if (!context.canPushRoute) return;

    if (!notification.isRead) {
      unawaited(viewModel.markAsRead(notification.id));
    }

    final type = notification.effectiveType;

    if (type.isDelayRequest) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DelayRequestDetailsScreen(notification: notification),
        ),
      );
      return;
    }

    // A module submitted for billing - opens a read-only detail with a
    // Continue button straight into Update Billing Status for that module
    // (see [BillingSubmittedDetailsScreen]), instead of the plain Billing
    // Management listing `openFor` falls back to below.
    if (type == NotificationType.projectSubmittedForBilling) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BillingSubmittedDetailsScreen(notification: notification),
        ),
      );
      return;
    }

    // A Revised Working Hours/End Date change request the PC submitted has
    // been approved - opens that module's own Module Details page directly
    // (see [ModuleDetailsScreen]) rather than the Approval queue's read-only
    // decision screen, since the PC's real next step is looking at the
    // module itself now that the change has taken effect.
    if (type == NotificationType.projectChangeApproved && notification.moduleId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ModuleDetailsScreen(moduleId: notification.moduleId!),
        ),
      );
      return;
    }

    // (projectChangeApproved is handled above, so this now only ever fires
    // for Requested/Rejected.)
    if (type.isChangeRequest && notification.changeRequestId != null) {
      final result = await DependencyInjection.approvalRepository
          .getChangeRequestDetails(notification.changeRequestId!);
      if (!context.mounted) return;
      final request = result.data as ProjectChangeRequest?;
      if (request != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ApprovalDetailsScreen(request: request)),
        );
        return;
      }
    }

    // A billing status reversion request the PC submitted has been approved
    // - looks up the matching BillingEntry (there is no single-module
    // billing GET, only the bulk list - see BillingRepository.getBillingList,
    // the same lookup BillingSubmittedDetailsScreen already does) and opens
    // UpdateBillingStatusScreen directly on it: the existing module-level
    // page within Billing Management, not the Approval queue's read-only
    // decision screen. Falls through to the generic billing-reversion
    // handling below only if the entry can't be found.
    if (type == NotificationType.billingReversionApproved && notification.moduleId != null) {
      final billingResult = await DependencyInjection.billingRepository.getBillingList();
      if (!context.mounted) return;
      final entries = (billingResult.data as List<BillingEntry>?) ?? [];
      BillingEntry? found;
      for (final entry in entries) {
        if (entry.moduleId == notification.moduleId) {
          found = entry;
          break;
        }
      }
      if (found != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UpdateBillingStatusScreen(entry: found!)),
        );
        return;
      }
    }

    // A billing status reversion request/decision - opens that specific
    // request's own detail screen directly (Captain can decide it there if
    // still pending; the requesting Project Controller sees the decision if
    // it's already been made), instead of the generic Captain-wide Approval
    // queue `openFor` falls back to below - which defaults to the Pending
    // tab and wouldn't even contain an already-decided request.
    // (billingReversionApproved is handled above when the module can be
    // found, so this now only ever fires for Requested/Rejected, or as a
    // fallback if that lookup failed.)
    if (type.isBillingReversion && notification.billingChangeRequestId != null) {
      final result = await DependencyInjection.billingRepository
          .getChangeRequestDetails(notification.billingChangeRequestId!);
      if (!context.mounted) return;
      final request = result.data as BillingStatusChangeRequest?;
      if (request != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BillingApprovalDetailsScreen(request: request)),
        );
        return;
      }
    }

    openFor(
      context: context,
      type: type,
      projectId: notification.projectId,
      moduleId: notification.moduleId,
    );
  }

  static void openFor({
    required BuildContext context,
    required NotificationType type,
    int? projectId,
    int? moduleId,
  }) {
    if (!context.canPushRoute) return;

    switch (type) {
      // Only ever sent to a project's Team Lead (see
      // `NotificationServiceImpl#notifyTimesheetSubmitted`).
      case NotificationType.timesheetSubmitted:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TimesheetApprovalListScreen()),
        );
        return;

      // Only ever sent to the employee whose timesheet was decided (see
      // `NotificationServiceImpl#notifyTimesheetDecision`), or who missed
      // logging a working day (see `WorkLogReminderScheduler`/
      // `NotificationServiceImpl#notifyTimesheetReminder`) - both land on
      // the same "My Timesheets" screen the employee needs next either way.
      case NotificationType.timesheetApproved:
      case NotificationType.timesheetRejected:
      case NotificationType.timesheetReminder:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TimesheetListScreen()),
        );
        return;

      // Sent only to the employee themselves once checked in for 9+ hours
      // with no check-out yet (see
      // `NotificationServiceImpl#notifyCheckoutReminder`) - opens the
      // Attendance screen directly so they can check out.
      case NotificationType.checkoutReminder:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AttendanceScreen()),
        );
        return;

      // Sent only to the module's assigned employees and its Team Lead (see
      // `NotificationServiceImpl#notifyModuleMilestone`) - opens that
      // module's own details page directly rather than the project's.
      case NotificationType.moduleMilestoneReached:
        if (moduleId == null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationListScreen()),
          );
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ModuleDetailsScreen(moduleId: moduleId),
          ),
        );
        return;

      // Sent to both the Team Lead and every team member - both open the
      // same plain, read-only project details screen. A deadline-extended
      // notification (an approved change request) is just as project-
      // centric as a plain update, so it shares this same routing. A low-
      // remaining-hours alert is module-specific, but the frontend
      // notification model doesn't carry a moduleId for it, so it routes to
      // the same project-level screen as the closest available fallback.
      // `projectMilestoneReached` is no longer generated (see
      // `MilestoneNotificationScheduler`) but stays routable here for any
      // historical rows.
      case NotificationType.projectCreated:
      case NotificationType.projectUpdated:
      case NotificationType.projectDeadlineExtended:
      case NotificationType.lowHoursRemaining:
      case NotificationType.projectMilestoneReached:
        if (projectId == null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationListScreen()),
          );
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProjectDetailsScreen(projectId: projectId),
          ),
        );
        return;

      // Reason for Delay / a change request - a fallback for callers that
      // can't build the full detail object needed for their respective
      // screens (see `PushNotificationService#_handleTapData` and
      // `openNotification` above, both of which fetch the full object first
      // and bypass this fallback); anything unrecognized also lands here.
      case NotificationType.delayRequested:
      case NotificationType.delayApproved:
      case NotificationType.delayRejected:
      case NotificationType.projectChangeRequested:
      case NotificationType.projectChangeApproved:
      case NotificationType.projectChangeRejected:
      case NotificationType.unknown:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationListScreen()),
        );
        return;

      // Sent to every Captain and Project Controller when a Team Lead
      // submits a project for billing (see `ProjectServiceImpl
      // #updateWorkStage` / `NotificationServiceImpl
      // #notifyProjectSubmittedForBilling`) - opens the Billing screen
      // directly, for both the in-app tap and the FCM push tap.
      case NotificationType.projectSubmittedForBilling:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BillingListScreen()),
        );
        return;

      // Sent to every Captain when a Project Controller requests reverting
      // a completed billing project back to Pending, and to the requesting
      // Project Controller once a Captain decides (see
      // `NotificationServiceImpl#notifyBillingReversionRequested`/
      // `#notifyBillingReversionDecision`). Both `openNotification` above
      // and `PushNotificationService#_handleTapData` already deep-link
      // straight to that specific request's own `BillingApprovalDetailsScreen`
      // before ever reaching this fallback - this generic Approval queue
      // (see [ApprovalListScreen]) only still runs for a notification with
      // no `billingChangeRequestId` (e.g. an older row from before this was
      // added).
      case NotificationType.billingReversionRequested:
      case NotificationType.billingReversionApproved:
      case NotificationType.billingReversionRejected:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ApprovalListScreen()),
        );
        return;
    }
  }
}
