import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The granular billing status selected on the Update Billing Status screen
/// - mirrors the backend's `com.comten.enums.BillingStatus` exactly (values
/// sent/received as these upper-snake-case names, see
/// `BillingServiceImpl#updateBillingStatus`). Distinct from
/// [BillingStage] (Pending/Completed), which is derived from this value
/// rather than chosen directly.
enum BillingStatus {
  invoiceYetToBeRaised,
  invoiceRaised,
  partPaymentReceived,
  fullPaymentReceived,
}

extension BillingStatusX on BillingStatus {
  String get label {
    switch (this) {
      case BillingStatus.invoiceYetToBeRaised:
        return 'Invoice yet to be raised';
      case BillingStatus.invoiceRaised:
        return 'Invoice raised';
      case BillingStatus.partPaymentReceived:
        return 'Part payment received';
      case BillingStatus.fullPaymentReceived:
        return 'Full payment received';
    }
  }

  String get apiValue {
    switch (this) {
      case BillingStatus.invoiceYetToBeRaised:
        return 'INVOICE_YET_TO_BE_RAISED';
      case BillingStatus.invoiceRaised:
        return 'INVOICE_RAISED';
      case BillingStatus.partPaymentReceived:
        return 'PART_PAYMENT_RECEIVED';
      case BillingStatus.fullPaymentReceived:
        return 'FULL_PAYMENT_RECEIVED';
    }
  }

  Color get color {
    switch (this) {
      case BillingStatus.invoiceYetToBeRaised:
        return AppColors.statusNotStarted;
      case BillingStatus.invoiceRaised:
        return AppColors.statusOnHold;
      case BillingStatus.partPaymentReceived:
        return AppColors.moduleBilling;
      case BillingStatus.fullPaymentReceived:
        return AppColors.statusActive;
    }
  }

  static BillingStatus fromApiValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'INVOICE_RAISED':
        return BillingStatus.invoiceRaised;
      case 'PART_PAYMENT_RECEIVED':
        return BillingStatus.partPaymentReceived;
      case 'FULL_PAYMENT_RECEIVED':
        return BillingStatus.fullPaymentReceived;
      default:
        return BillingStatus.invoiceYetToBeRaised;
    }
  }
}
