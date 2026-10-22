import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/widgets/app_card.dart';
import '../model/project_change_request.dart';

/// A single request row on [ApprovalListScreen] - project identity, who
/// requested it, and what's being proposed, plus a status badge.
class ApprovalCard extends StatelessWidget {
  final ProjectChangeRequest request;
  final VoidCallback onTap;

  const ApprovalCard({
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
          if (request.changesEndDate) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.event_outlined, size: 16, color: AppColors.textSecondaryFor(context)),
                const SizedBox(width: 6),
                Text(
                  'New end date: ${_formatDate(request.proposedEndDate!)}',
                  style: TextStyle(color: AppColors.textSecondaryFor(context)),
                ),
              ],
            ),
          ],
          if (request.changesEstimatedHours) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.timelapse_outlined, size: 16, color: AppColors.textSecondaryFor(context)),
                const SizedBox(width: 6),
                Text(
                  'New estimated hours: '
                  '${DurationFormatter.humanReadable(request.proposedEstimatedMinutes)}',
                  style: TextStyle(color: AppColors.textSecondaryFor(context)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime value) => '${value.day}/${value.month}/${value.year}';
}
