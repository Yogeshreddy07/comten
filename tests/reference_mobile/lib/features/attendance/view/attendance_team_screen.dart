import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../model/team_attendance_entry.dart';
import '../viewmodel/attendance_team_view_model.dart';
import '../widgets/attendance_card.dart';
import 'attendance_details_screen.dart';

/// Team Attendance - Team Leader landing screen for the Attendance module.
/// Shows today's attendance by default; the date field opens a calendar
/// picker so any past date can be viewed instead. Every member of a project
/// this Team Leader leads is listed (scoped server-side, see
/// `AttendanceServiceImpl#getTeamAttendance`), including members who
/// haven't checked in for the selected date. [AttendanceTeamViewModel] is
/// provided app-wide (see main.dart).
class AttendanceTeamScreen extends StatefulWidget {
  const AttendanceTeamScreen({super.key});

  @override
  State<AttendanceTeamScreen> createState() => _AttendanceTeamScreenState();
}

class _AttendanceTeamScreenState extends State<AttendanceTeamScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AttendanceTeamViewModel>().fetchTeamAttendance();
    });
  }

  Future<void> _pickDate(BuildContext context) async {
    final viewModel = context.read<AttendanceTeamViewModel>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: viewModel.selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null || !context.mounted) return;
    context.read<AttendanceTeamViewModel>().fetchTeamAttendance(date: picked);
  }

  void _openDetails(BuildContext context, TeamAttendanceEntry entry) {
    if (!context.canPushRoute) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceDetailsScreen(entry: entry),
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AttendanceTeamViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.attendanceTeamTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _DateField(
              date: viewModel.selectedDate,
              isToday: _isToday(viewModel.selectedDate),
              onTap: () => _pickDate(context),
            ),
            Expanded(child: _buildBody(context, viewModel)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AttendanceTeamViewModel viewModel) {
    switch (viewModel.loadState) {
      case AttendanceTeamLoadState.initial:
      case AttendanceTeamLoadState.loading:
        return const AppLoader(message: AppStrings.attendanceTeamLoading);

      case AttendanceTeamLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.attendanceTeamLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchTeamAttendance(),
        );

      case AttendanceTeamLoadState.success:
        if (viewModel.records.isEmpty) {
          return const AppEmptyView(
            icon: Icons.fact_check_outlined,
            title: AppStrings.attendanceTeamEmptyTitle,
            message: AppStrings.attendanceTeamEmptyMessage,
          );
        }

        return RefreshIndicator(
          onRefresh: () => viewModel.fetchTeamAttendance(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: viewModel.records.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final record = viewModel.records[index];
              return AttendanceCard(
                entry: record,
                onTap: () => _openDetails(context, record),
              );
            },
          ),
        );
    }
  }
}

class _DateField extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final VoidCallback onTap;

  const _DateField({
    required this.date,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.textSecondaryFor(context).withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isToday
                      ? '${AppStrings.attendanceFilterToday} · ${DateFormatter.format(date)}'
                      : DateFormatter.format(date),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
