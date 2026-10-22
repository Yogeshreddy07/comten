import '../../../shared/enums/approval_status.dart';
import '../../billing/model/billing_status_change_request.dart';
import 'project_change_request.dart';
import 'project_deactivation_request.dart';

enum ApprovalQueueItemType { projectChange, billingReversion, projectDeactivation }

/// A single row in the Captain's unified Approval queue - a
/// [ProjectChangeRequest] (End Date/Estimated Hours), a
/// [BillingStatusChangeRequest] (Completed -> Pending billing reversion), or
/// a [ProjectDeactivationRequest] (deactivating a project already in Billing
/// Management). The request types are decided through separate backend
/// endpoints but are shown together here so the Captain has one place to
/// review everything pending a decision.
class ApprovalQueueItem {
  final ApprovalQueueItemType type;
  final ProjectChangeRequest? projectChangeRequest;
  final BillingStatusChangeRequest? billingStatusChangeRequest;
  final ProjectDeactivationRequest? projectDeactivationRequest;

  const ApprovalQueueItem.projectChange(ProjectChangeRequest request)
      : type = ApprovalQueueItemType.projectChange,
        projectChangeRequest = request,
        billingStatusChangeRequest = null,
        projectDeactivationRequest = null;

  const ApprovalQueueItem.billingReversion(BillingStatusChangeRequest request)
      : type = ApprovalQueueItemType.billingReversion,
        projectChangeRequest = null,
        billingStatusChangeRequest = request,
        projectDeactivationRequest = null;

  const ApprovalQueueItem.projectDeactivation(ProjectDeactivationRequest request)
      : type = ApprovalQueueItemType.projectDeactivation,
        projectChangeRequest = null,
        billingStatusChangeRequest = null,
        projectDeactivationRequest = request;

  ApprovalStatus get effectiveStatus => switch (type) {
        ApprovalQueueItemType.projectChange =>
          projectChangeRequest!.effectiveStatus,
        ApprovalQueueItemType.billingReversion =>
          billingStatusChangeRequest!.effectiveStatus,
        ApprovalQueueItemType.projectDeactivation =>
          projectDeactivationRequest!.effectiveStatus,
      };

  DateTime get createdAt =>
      switch (type) {
        ApprovalQueueItemType.projectChange => projectChangeRequest!.createdAt,
        ApprovalQueueItemType.billingReversion =>
          billingStatusChangeRequest!.createdAt,
        ApprovalQueueItemType.projectDeactivation =>
          projectDeactivationRequest!.createdAt,
      } ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
