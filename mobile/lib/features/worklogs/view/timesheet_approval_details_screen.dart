import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/dialogs/reject_timesheet_dialog.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../projects/widgets/review_summary_card.dart';
import '../model/work_log.dart';
import '../utils/work_log_duration_formatter.dart';
import '../viewmodel/work_log_approval_view_model.dart';

/// Timesheet detail + approve/reject actions for the project's Team Leader.
/// The [WorkLog] is passed in directly from
/// [TimesheetApprovalListScreen] - the list endpoint already returns every
/// field this screen needs - and refreshed locally whenever an action
/// succeeds via [WorkLogApprovalViewModel].
class TimesheetApprovalDetailsScreen extends StatefulWidget {
  final WorkLog workLog;

  const TimesheetApprovalDetailsScreen({super.key, required this.workLog});

  @override
  State<TimesheetApprovalDetailsScreen> createState() =>
      _TimesheetApprovalDetailsScreenState();
}

enum _PendingAction { none, approve, reject }

class _TimesheetApprovalDetailsScreenState
    extends State<TimesheetApprovalDetailsScreen> {
  late WorkLog _workLog;

  // Which button's spinner should show - `viewModel.isProcessing` alone
  // can't tell them apart, since it's shared by both actions (so Approve
  // stays disabled while Reject is in flight, and vice versa); this is
  // purely for which one of the two displays a spinner.
  _PendingAction _pendingAction = _PendingAction.none;

  @override
  void initState() {
    super.initState();
    _workLog = widget.workLog;
  }

  Future<void> _approve() async {
    final viewModel = context.read<WorkLogApprovalViewModel>();
    if (viewModel.isProcessing) return;
    setState(() => _pendingAction = _PendingAction.approve);
    final result = await viewModel.approveWorkLog(_workLog.id);
    if (!mounted) return;
    setState(() => _pendingAction = _PendingAction.none);

    if (result.success) {
      setState(() => _workLog = (result.data as WorkLog?) ?? _workLog);
      SnackbarUtil.showSuccess(context, AppStrings.timesheetApproveSuccess);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  Future<void> _reject() async {
    if (context.read<WorkLogApprovalViewModel>().isProcessing) return;

    final reason = await RejectTimesheetDialog.show(context);
    if (reason == null || !mounted) return;

    final viewModel = context.read<WorkLogApprovalViewModel>();
    if (viewModel.isProcessing) return;
    setState(() => _pendingAction = _PendingAction.reject);
    final result = await viewModel.rejectWorkLog(_workLog.id, reason);
    if (!mounted) return;
    setState(() => _pendingAction = _PendingAction.none);

    if (result.success) {
      setState(() => _workLog = (result.data as WorkLog?) ?? _workLog);
      SnackbarUtil.showSuccess(context, AppStrings.timesheetRejectSuccess);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<WorkLogApprovalViewModel>();
    final status = ApprovalStatusX.fromApiValue(_workLog.approvalStatus);
    final isPending = status == ApprovalStatus.pending;

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
                            _workLog.projectName,
                            style:
                                AppTextStyles.heading.copyWith(fontSize: 20),
                          ),
                        ),
                        _StatusBadge(status: status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Project ID: ${_workLog.projectCode}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ReviewSummarySection(
                title: 'Employee',
                rows: [
                  ReviewDetailRow('Name', _workLog.employeeName),
                  ReviewDetailRow('Employee Code', _workLog.employeeCode),
                ],
              ),
              const SizedBox(height: 16),
              ReviewSummarySection(
                title: 'Timesheet Information',
                rows: [
                  ReviewDetailRow(
                    'Work Date',
                    DateFormatter.format(_workLog.workDate),
                  ),
                  if (_workLog.billableDurationSeconds != null)
                    ReviewDetailRow(
                      AppStrings.billableHoursWorkedLabel,
                      WorkLogDurationFormatter.format(_workLog.billableDurationSeconds!),
                    ),
                  if (_workLog.nonBillableDurationSeconds != null)
                    ReviewDetailRow(
                      AppStrings.nonBillableHoursWorkedLabel,
                      WorkLogDurationFormatter.format(_workLog.nonBillableDurationSeconds!),
                    ),
                  ReviewDetailRow('Work Done', _workLog.workDone),
                ],
              ),
              if (_workLog.billableActivities.isNotEmpty ||
                  _workLog.nonBillableActivities.isNotEmpty) ...[
                const SizedBox(height: 16),
                ReviewSummarySection(
                  title: AppStrings.dashboardModuleActivities,
                  rows: [
                    if (_workLog.billableActivities.isNotEmpty)
                      ReviewDetailRow(
                        AppStrings.billableActivitiesLabel,
                        _workLog.billableActivities
                            .map((a) => a.name)
                            .join(', '),
                      ),
                    if (_workLog.nonBillableActivities.isNotEmpty)
                      ReviewDetailRow(
                        AppStrings.nonBillableActivitiesLabel,
                        _workLog.nonBillableActivities
                            .map((a) => a.name)
                            .join(', '),
                      ),
                  ],
                ),
              ],
              if (status == ApprovalStatus.rejected &&
                  (_workLog.rejectionReason ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                ReviewSummarySection(
                  title: AppStrings.timesheetRejectionReasonLabel,
                  rows: [
                    ReviewDetailRow('Reason', _workLog.rejectionReason!),
                  ],
                ),
              ],
              if (isPending) ...[
                const SizedBox(height: AppDimensions.sectionSpacing),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: AppStrings.timesheetRejectButton,
                        outlined: true,
                        isLoading: _pendingAction == _PendingAction.reject,
                        onPressed: viewModel.isProcessing ? null : _reject,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.cardSpacing),
                    Expanded(
                      child: AppButton(
                        text: AppStrings.timesheetApproveButton,
                        isLoading: _pendingAction == _PendingAction.approve,
                        onPressed: viewModel.isProcessing ? null : _approve,
                      ),
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
