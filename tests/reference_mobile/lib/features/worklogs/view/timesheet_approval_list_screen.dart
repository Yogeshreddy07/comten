import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../model/work_log.dart';
import '../viewmodel/work_log_approval_view_model.dart';
import '../widgets/timesheet_card.dart';
import 'timesheet_approval_details_screen.dart';

/// Timesheet Approvals queue - Team Leader landing screen for the Working
/// Hours module, scoped server-side to entries submitted against projects
/// this Team Leader leads. [WorkLogApprovalViewModel] is provided app-wide
/// (see main.dart) so the list stays in sync after an approve/reject action
/// on the details screen pops back here.
class TimesheetApprovalListScreen extends StatefulWidget {
  const TimesheetApprovalListScreen({super.key});

  @override
  State<TimesheetApprovalListScreen> createState() =>
      _TimesheetApprovalListScreenState();
}

class _TimesheetApprovalListScreenState
    extends State<TimesheetApprovalListScreen> {
  ApprovalStatus? _statusFilter = ApprovalStatus.pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetch();
    });
  }

  void _fetch() {
    context.read<WorkLogApprovalViewModel>().fetchWorkLogs(
          status: _statusFilter?.apiValue,
        );
  }

  void _openDetails(BuildContext context, WorkLog workLog) {
    if (!context.canPushRoute) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TimesheetApprovalDetailsScreen(workLog: workLog),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<WorkLogApprovalViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.timesheetApprovalListTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _FilterChips(
              selected: _statusFilter,
              onChanged: (value) {
                setState(() => _statusFilter = value);
                _fetch();
              },
            ),
            Expanded(child: _buildBody(context, viewModel)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WorkLogApprovalViewModel viewModel) {
    switch (viewModel.loadState) {
      case WorkLogApprovalLoadState.initial:
      case WorkLogApprovalLoadState.loading:
        return const AppLoader(message: AppStrings.timesheetApprovalListLoading);

      case WorkLogApprovalLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.timesheetApprovalListLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: _fetch,
        );

      case WorkLogApprovalLoadState.success:
        if (viewModel.workLogs.isEmpty) {
          return const AppEmptyView(
            icon: Icons.schedule_outlined,
            title: AppStrings.timesheetApprovalListEmptyTitle,
            message: AppStrings.timesheetApprovalListEmptyMessage,
          );
        }

        return RefreshIndicator(
          onRefresh: () async => _fetch(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: viewModel.workLogs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final workLog = viewModel.workLogs[index];
              return TimesheetCard(
                workLog: workLog,
                showEmployeeName: true,
                onTap: () => _openDetails(context, workLog),
              );
            },
          ),
        );
    }
  }
}

class _FilterChips extends StatelessWidget {
  final ApprovalStatus? selected;
  final ValueChanged<ApprovalStatus?> onChanged;

  const _FilterChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = <(ApprovalStatus?, String)>[
      (null, AppStrings.timesheetFilterAll),
      (ApprovalStatus.pending, AppStrings.timesheetFilterPending),
      (ApprovalStatus.approved, AppStrings.timesheetFilterApproved),
      (ApprovalStatus.rejected, AppStrings.timesheetFilterRejected),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final option in options)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(option.$2),
                  selected: selected == option.$1,
                  onSelected: (_) => onChanged(option.$1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
