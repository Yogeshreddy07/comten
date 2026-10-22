import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/team_attendance_status.dart';
import '../../../shared/widgets/app_card.dart';
import '../model/team_attendance_entry.dart';

/// A single team member's attendance row for [AttendanceTeamScreen] - one
/// employee's status for the currently selected date: not checked in yet,
/// checked in (with the check-in time), or checked out (with both times).
class AttendanceCard extends StatelessWidget {
  final TeamAttendanceEntry entry;
  final VoidCallback onTap;

  const AttendanceCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final status = entry.effectiveStatus;

    return AppCard(
      onTap: entry.hasAttendanceRecord ? onTap : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.employeeName,
                  style: AppTextStyles.subHeading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
          if (entry.hasAttendanceRecord) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.login, size: 15, color: AppColors.textSecondaryFor(context)),
                const SizedBox(width: 6),
                Text(
                  _formatTime(entry.inTime!),
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondaryFor(context)),
                ),
                const SizedBox(width: 16),
                Icon(Icons.logout, size: 15, color: AppColors.textSecondaryFor(context)),
                const SizedBox(width: 6),
                Text(
                  entry.outTime != null
                      ? _formatTime(entry.outTime!)
                      : AppStrings.attendanceNotCheckedOutYet,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondaryFor(context)),
                ),
              ],
            ),
            if (entry.locationName != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 15, color: AppColors.textSecondaryFor(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.locationName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TeamAttendanceStatus status;

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
