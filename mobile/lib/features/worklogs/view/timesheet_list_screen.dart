import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../model/work_log.dart';
import '../viewmodel/work_log_view_model.dart';
import '../widgets/timesheet_card.dart';
import 'submit_timesheet_screen.dart';
import 'timesheet_details_screen.dart';

/// "My Timesheets" - Employee landing screen for the Working Hours module.
/// [WorkLogViewModel] is provided app-wide (see main.dart) so the list
/// stays in sync after the Submit screen pops.
class TimesheetListScreen extends StatefulWidget {
  const TimesheetListScreen({super.key});

  @override
  State<TimesheetListScreen> createState() => _TimesheetListScreenState();
}

class _TimesheetListScreenState extends State<TimesheetListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final viewModel = context.read<WorkLogViewModel>();
      viewModel.fetchMyWorkLogs();
      _checkPendingReminder(context);
    });
  }

  /// Re-checked every time this screen opens (not just once) - shown again
  /// on every visit until the missing day's entry is actually completed.
  Future<void> _checkPendingReminder(BuildContext context) async {
    final viewModel = context.read<WorkLogViewModel>();
    await viewModel.fetchPendingReminder();
    if (!context.mounted) return;

    final dayLabel = viewModel.pendingReminderDayLabel;
    if (dayLabel == null) return;
    if (!context.canPushRoute) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.timesheetReminderTitle),
        content: Text(AppStrings.timesheetReminderMessage(dayLabel)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(AppStrings.timesheetReminderDismiss),
          ),
        ],
      ),
    );
  }

  Future<void> _openSubmit(BuildContext context) async {
    if (!context.canPushRoute) return;
    final message = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const SubmitTimesheetScreen()),
    );
    if (!context.mounted) return;
    if (message != null) {
      SnackbarUtil.showSuccess(context, message);
    } else {
      context.read<WorkLogViewModel>().fetchMyWorkLogs();
    }
  }

  void _openDetails(BuildContext context, WorkLog workLog) {
    if (!context.canPushRoute) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TimesheetDetailsScreen(workLog: workLog),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<WorkLogViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.timesheetListTitle),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(context, viewModel)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSubmit(context),
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.timesheetListAddButton),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WorkLogViewModel viewModel) {
    switch (viewModel.loadState) {
      case WorkLogLoadState.initial:
      case WorkLogLoadState.loading:
        return const AppLoader(message: AppStrings.timesheetListLoading);

      case WorkLogLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.timesheetListLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchMyWorkLogs(),
        );

      case WorkLogLoadState.success:
        if (viewModel.workLogs.isEmpty) {
          return const AppEmptyView(
            icon: Icons.schedule_outlined,
            title: AppStrings.timesheetListEmptyTitle,
            message: AppStrings.timesheetListEmptyMessage,
          );
        }

        return RefreshIndicator(
          onRefresh: viewModel.fetchMyWorkLogs,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: viewModel.workLogs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final workLog = viewModel.workLogs[index];
              return TimesheetCard(
                workLog: workLog,
                onTap: () => _openDetails(context, workLog),
              );
            },
          ),
        );
    }
  }
}
