import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/enums/billing_status.dart';
import '../../../shared/widgets/app_card.dart';
import '../model/billing_status_change_request.dart';

/// A single request row on the unified Approval screen - project identity,
/// who requested it, and the current -> proposed status change, plus a
/// status badge.
class BillingApprovalCard extends StatelessWidget {
  final BillingStatusChangeRequest request;
  final VoidCallback onTap;

  const BillingApprovalCard({
    super.key,
    required this.request,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = request.effectiveStatus;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.projectName,
                      style: AppTextStyles.subHeading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${request.projectCode}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: status.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person_outline, size: 16, color: AppColors.textSecondaryFor(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Requested by ${request.requestedByName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondaryFor(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.textSecondaryFor(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${BillingStatusX.fromApiValue(request.currentStatus).label} '
                  '→ ${BillingStatusX.fromApiValue(request.proposedStatus).label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondaryFor(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
