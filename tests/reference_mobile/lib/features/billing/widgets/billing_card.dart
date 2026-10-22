import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/project_status.dart';
import '../../../shared/widgets/app_card.dart';
import '../model/billing_entry.dart';

/// A single module row on [BillingListScreen] - module identity (heading)
/// with its parent project (subtitle), Team Lead, current SPOC, and module
/// status. Billing status itself (Pending/Completed/To Be Billed/Invoice
/// Raised etc.) is deliberately not shown here - only the dedicated
/// billing-status screens surface it, including for a module parked in
/// Completed by project deactivation.
class BillingCard extends StatelessWidget {
  final BillingEntry entry;
  final VoidCallback onTap;

  const BillingCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                      entry.moduleName,
                      style: AppTextStyles.subHeading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.projectName} (ID: ${entry.projectCode})',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryFor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (entry.moduleStatus != null)
                _ModuleStatusBadge(moduleStatus: entry.moduleStatus!),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.badge_outlined,
                  size: 16, color: AppColors.textSecondaryFor(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.teamLeadName?.isNotEmpty == true
                      ? entry.teamLeadName!
                      : AppStrings.billingTeamLeadNotSet,
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
              Icon(Icons.person_outline,
                  size: 16, color: AppColors.textSecondaryFor(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.spocName?.isNotEmpty == true
                      ? entry.spocName!
                      : AppStrings.billingSpocNotSet,
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

/// The module's work status (In Progress / Completed / etc.).
class _ModuleStatusBadge extends StatelessWidget {
  final String moduleStatus;

  const _ModuleStatusBadge({required this.moduleStatus});

  @override
  Widget build(BuildContext context) {
    final status = ProjectStatusX.fromApiValue(moduleStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: status.color,
        ),
      ),
    );
  }
}
