import '../../../shared/enums/notification_type.dart';

/// A single notification - mirrors the backend's `NotificationResponse`
/// exactly (see `GET /api/notifications`). [reason] is only populated for
/// `DELAY_REQUESTED` notifications - purely informational content, with no
/// decision/approval state attached.
class NotificationItem {
  final int id;
  final String type;
  final String title;
  final String message;

  final int? moduleId;
  final String? moduleName;

  final int? projectId;
  final String? projectCode;
  final String? projectName;

  final int? senderId;
  final String? senderName;

  final String? reason;

  /// Only populated for `PROJECT_CHANGE_REQUESTED`/`_APPROVED`/`_REJECTED`.
  final int? changeRequestId;

  /// Only populated for `BILLING_REVERSION_REQUESTED`/`_APPROVED`/`_REJECTED`.
  final int? billingChangeRequestId;

  /// Only populated for `MODULE_MILESTONE_REACHED` - the exact threshold
  /// (30/60/90) crossed, used to pick the alert color (green/yellow/red).
  final int? milestonePercent;

  final bool isRead;
  final DateTime createdAt;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.moduleId,
    this.moduleName,
    this.projectId,
    this.projectCode,
    this.projectName,
    this.senderId,
    this.senderName,
    this.reason,
    this.changeRequestId,
    this.billingChangeRequestId,
    this.milestonePercent,
    required this.isRead,
    required this.createdAt,
  });

  NotificationType get effectiveType => NotificationTypeX.fromApiValue(type);

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as int,
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      moduleId: json['moduleId'] as int?,
      moduleName: json['moduleName'] as String?,
      projectId: json['projectId'] as int?,
      projectCode: json['projectCode'] as String?,
      projectName: json['projectName'] as String?,
      senderId: json['senderId'] as int?,
      senderName: json['senderName'] as String?,
      reason: json['reason'] as String?,
      changeRequestId: json['changeRequestId'] as int?,
      billingChangeRequestId: json['billingChangeRequestId'] as int?,
      milestonePercent: json['milestonePercent'] as int?,
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    );
  }

  NotificationItem copyWith({bool? isRead}) {
    return NotificationItem(
      id: id,
      type: type,
      title: title,
      message: message,
      moduleId: moduleId,
      moduleName: moduleName,
      projectId: projectId,
      projectCode: projectCode,
      projectName: projectName,
      senderId: senderId,
      senderName: senderName,
      reason: reason,
      changeRequestId: changeRequestId,
      billingChangeRequestId: billingChangeRequestId,
      milestonePercent: milestonePercent,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}
