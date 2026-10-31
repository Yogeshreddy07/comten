import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/widgets/app_card.dart';
import '../../projects/widgets/review_summary_card.dart';
import '../model/work_log.dart';
import '../utils/work_log_duration_formatter.dart';

/// Read-only detail view of a single timesheet entry, for the Employee who
/// submitted it. The full [WorkLog] is passed in directly
/// from [TimesheetListScreen] - the list endpoint already returns every
/// field the detail view needs, so no extra round trip is made.
class TimesheetDetailsScreen extends StatelessWidget {
  final WorkLog workLog;

  const TimesheetDetailsScreen({super.key, required this.workLog});

  @override
  Widget build(BuildContext context) {
    final status = ApprovalStatusX.fromApiValue(workLog.approvalStatus);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.timesheetDetailsTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            workLog.projectName,
                            style:
                                AppTextStyles.heading.copyWith(fontSize: 20),
                          ),
                        ),
                        _StatusBadge(status: status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Project ID: ${workLog.projectCode}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ReviewSummarySection(
                title: 'Timesheet Information',
                rows: [
                  ReviewDetailRow(
                    'Work Date',
                    DateFormatter.format(workLog.workDate),
                  ),
                  if (workLog.billableDurationSeconds != null)
                    ReviewDetailRow(
                      AppStrings.billableHoursWorkedLabel,
                      WorkLogDurationFormatter.format(workLog.billableDurationSeconds!),
                    ),
                  if (workLog.nonBillableDurationSeconds != null)
                    ReviewDetailRow(
                      AppStrings.nonBillableHoursWorkedLabel,
                      WorkLogDurationFormatter.format(workLog.nonBillableDurationSeconds!),
                    ),
                  ReviewDetailRow('Work Done', workLog.workDone),
                ],
              ),
              if (workLog.billableActivities.isNotEmpty ||
                  workLog.nonBillableActivities.isNotEmpty) ...[
                const SizedBox(height: 16),
                ReviewSummarySection(
                  title: AppStrings.dashboardModuleActivities,
                  rows: [
                    if (workLog.billableActivities.isNotEmpty)
                      ReviewDetailRow(
                        AppStrings.billableActivitiesLabel,
                        workLog.billableActivities
                            .map((a) => a.name)
                            .join(', '),
                      ),
                    if (workLog.nonBillableActivities.isNotEmpty)
                      ReviewDetailRow(
                        AppStrings.nonBillableActivitiesLabel,
                        workLog.nonBillableActivities
                            .map((a) => a.name)
                            .join(', '),
                      ),
                  ],
                ),
              ],
              if (status == ApprovalStatus.rejected &&
                  (workLog.rejectionReason ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                ReviewSummarySection(
                  title: AppStrings.timesheetRejectionReasonLabel,
                  rows: [
                    ReviewDetailRow('Reason', workLog.rejectionReason!),
                  ],
                ),
              ],
              if (status == ApprovalStatus.approved &&
                  workLog.approvedByName != null) ...[
                const SizedBox(height: 16),
                ReviewSummarySection(
                  title: 'Approval',
                  rows: [
                    ReviewDetailRow(
                      AppStrings.timesheetApprovedByLabel,
                      workLog.approvedByName!,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontWeight: FontWeight.w600, color: status.color),
      ),
    );
  }
}
