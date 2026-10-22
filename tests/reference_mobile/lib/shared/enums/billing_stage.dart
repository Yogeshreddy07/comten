import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'billing_status.dart';

/// Derived (never chosen directly) grouping of a [BillingStatus] for the
/// Billing Management screen's To Be Billed / Pending / Completed tabs -
/// mirrors the backend's `com.comten.enums.BillingStage` exactly.
/// [BillingStatus.invoiceYetToBeRaised] maps to [BillingStage.toBeBilled],
/// [BillingStatus.fullPaymentReceived] maps to [BillingStage.completed], and
/// everything else maps to [BillingStage.pending].
enum BillingStage {
  toBeBilled,
  pending,
  completed,
}

extension BillingStageX on BillingStage {
  String get label {
    switch (this) {
      case BillingStage.toBeBilled:
        return 'To Be Billed';
      case BillingStage.pending:
        return 'Pending';
      case BillingStage.completed:
        return 'Completed';
    }
  }

  String get apiValue {
    switch (this) {
      case BillingStage.toBeBilled:
        return 'TO_BE_BILLED';
      case BillingStage.pending:
        return 'PENDING';
      case BillingStage.completed:
        return 'COMPLETED';
    }
  }

  Color get color {
    switch (this) {
      case BillingStage.toBeBilled:
        return AppColors.statusNotStarted;
      case BillingStage.pending:
        return AppColors.statusOnHold;
      case BillingStage.completed:
        return AppColors.statusActive;
    }
  }

  static BillingStage forStatus(BillingStatus status) {
    if (status == BillingStatus.invoiceYetToBeRaised) return BillingStage.toBeBilled;
    if (status == BillingStatus.fullPaymentReceived) return BillingStage.completed;
    return BillingStage.pending;
  }

  /// `value == null` means the project has no billing record yet - treated
  /// as [BillingStage.toBeBilled] for the three-tab split (see
  /// `BillingEntry.effectiveStage`).
  static BillingStage fromApiValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'PENDING':
        return BillingStage.pending;
      case 'COMPLETED':
        return BillingStage.completed;
      default:
        return BillingStage.toBeBilled;
    }
  }
}
