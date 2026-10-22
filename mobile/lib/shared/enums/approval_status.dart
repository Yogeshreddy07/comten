import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Mirrors the backend's `com.comten.enums.ApprovalStatus` exactly - values
/// are sent/received as these upper-snake-case names (see
/// `WorkLogServiceImpl#requirePendingStatus`).
enum ApprovalStatus {
  pending,
  approved,
  rejected,
}

extension ApprovalStatusX on ApprovalStatus {
  String get label {
    switch (this) {
      case ApprovalStatus.pending:
        return 'Pending';
      case ApprovalStatus.approved:
        return 'Approved';
      case ApprovalStatus.rejected:
        return 'Rejected';
    }
  }

  String get apiValue {
    switch (this) {
      case ApprovalStatus.pending:
        return 'PENDING';
      case ApprovalStatus.approved:
        return 'APPROVED';
      case ApprovalStatus.rejected:
        return 'REJECTED';
    }
  }

  Color get color {
    switch (this) {
      case ApprovalStatus.pending:
        return AppColors.statusOnHold;
      case ApprovalStatus.approved:
        return AppColors.statusActive;
      case ApprovalStatus.rejected:
        return AppColors.statusCancelled;
    }
  }

  static ApprovalStatus fromApiValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'APPROVED':
        return ApprovalStatus.approved;
      case 'REJECTED':
        return ApprovalStatus.rejected;
      default:
        return ApprovalStatus.pending;
    }
  }
}
