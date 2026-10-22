import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/widgets/app_card.dart';
import '../model/work_log.dart';
import '../utils/work_log_duration_formatter.dart';

/// A single timesheet row - reused by both [TimesheetListScreen] (Employee,
/// [showEmployeeName] false) and [TimesheetApprovalListScreen] (Team Leader,
/// [showEmployeeName] true).
class TimesheetCard extends StatelessWidget {
  final WorkLog workLog;
  final bool showEmployeeName;
  final VoidCallback onTap;

  const TimesheetCard({
    super.key,
    required this.workLog,
    required this.onTap,
    this.showEmployeeName = false,
  });

  @override
  Widget build(BuildContext context) {
    final status = ApprovalStatusX.fromApiValue(workLog.approvalStatus);

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
                      workLog.projectName,
                      style: AppTextStyles.subHeading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      showEmployeeName
                          ? workLog.employeeName
                          : 'ID: ${workLog.projectCode}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 15, color: AppColors.textSecondaryFor(context)),
              const SizedBox(width: 6),
              Text(
                DateFormatter.format(workLog.workDate),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
              const Spacer(),
              Icon(Icons.schedule_outlined,
                  size: 15, color: AppColors.textSecondaryFor(context)),
              const SizedBox(width: 6),
              // Billable and Non-Billable are shown as their own lines - a log
              // can carry either or both, never a blended total - matching the
              // detail screens' split rows.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (workLog.billableDurationSeconds != null)
                    _DurationLine(
                      label: 'Billable',
                      value: WorkLogDurationFormatter.formatCompact(
                          workLog.billableDurationSeconds!),
                    ),
                  if (workLog.nonBillableDurationSeconds != null)
                    _DurationLine(
                      label: 'Non-Billable',
                      value: WorkLogDurationFormatter.formatCompact(
                          workLog.nonBillableDurationSeconds!),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DurationLine extends StatelessWidget {
  final String label;
  final String value;

  const _DurationLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondaryFor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label ', style: TextStyle(fontSize: 11, color: secondary)),
            TextSpan(
              text: value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondary),
            ),
          ],
        ),
        textAlign: TextAlign.right,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ApprovalStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}
