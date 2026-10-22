import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/enums/project_status.dart';
import '../../../shared/widgets/app_card.dart';
import '../model/module_list_item.dart';

/// A single module row on [ProjectDetailsScreen]'s module list - name, Team
/// Lead, date range, and status badge.
class ModuleCard extends StatelessWidget {
  final ModuleListItem module;
  final VoidCallback onTap;

  const ModuleCard({
    super.key,
    required this.module,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = ProjectStatusX.fromApiValue(module.status);

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  module.moduleName,
                  style: AppTextStyles.subHeading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
              Icon(Icons.supervisor_account_outlined,
                  size: 16, color: AppColors.textSecondaryFor(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  module.teamLeadName ?? 'Unassigned',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondaryFor(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 15, color: AppColors.textSecondaryFor(context)),
              const SizedBox(width: 6),
              Text(
                '${DateFormatter.formatNullable(module.startDate) ?? '-'} - '
                '${DateFormatter.formatNullable(module.endDate) ?? '-'}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
