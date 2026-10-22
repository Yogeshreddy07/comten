import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/location_helper.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/attendance_type.dart';
import '../../../shared/widgets/app_card.dart';
import '../../projects/widgets/review_summary_card.dart';
import '../model/team_attendance_entry.dart';

/// Read-only detail view of a single team member's attendance for the
/// selected date, reached by a Team Leader tapping a row in
/// [AttendanceTeamScreen] (only enabled once a record exists). The full
/// [TeamAttendanceEntry] is passed in directly from the list - the team
/// endpoint already returns every field this screen needs, so no extra
/// round trip is made.
class AttendanceDetailsScreen extends StatelessWidget {
  final TeamAttendanceEntry entry;

  const AttendanceDetailsScreen({super.key, required this.entry});

  String _formatDateTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${DateFormatter.format(value)}, $hour:$minute';
  }

  String _formatLocation(String? name, double? latitude, double? longitude) {
    if (name != null && name.isNotEmpty) {
      return LocationHelper.trimTrailingAfterCountry(name) ?? name;
    }
    if (latitude == null || longitude == null) {
      return AppStrings.attendanceNotCheckedOutYet;
    }
    // Reverse geocoding failed for this check-in/out (offline, unsupported
    // platform, or no placemark found) - show a plain label instead of raw
    // coordinates, which read as unexplained numbers rather than a location.
    return AppStrings.attendanceLocationNameUnavailable;
  }

  @override
  Widget build(BuildContext context) {
    final type = AttendanceTypeX.fromApiValue(entry.attendanceType);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.attendanceDetailsTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.employeeName,
                            style: AppTextStyles.heading.copyWith(fontSize: 20),
                          ),
                          const SizedBox(height: 4),
                          Text('Employee Code: ${entry.employeeCode}'),
                        ],
                      ),
                    ),
                    Icon(type.icon),
                    const SizedBox(width: 6),
                    Text(type.label),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ReviewSummarySection(
                title: 'Attendance Information',
                rows: [
                  ReviewDetailRow(
                    'Date',
                    DateFormatter.format(entry.attendanceDate),
                  ),
                  ReviewDetailRow(AppStrings.attendanceFieldWorkMode, type.label),
                ],
              ),
              const SizedBox(height: 16),
              ReviewSummarySection(
                title: AppStrings.attendanceFieldCheckInTime,
                rows: [
                  ReviewDetailRow(
                    'Time',
                    entry.inTime != null
                        ? _formatDateTime(entry.inTime!)
                        : AppStrings.attendanceNotCheckedOutYet,
                  ),
                  ReviewDetailRow(
                    AppStrings.attendanceFieldCheckInLocation,
                    _formatLocation(
                      entry.locationName,
                      entry.latitude,
                      entry.longitude,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ReviewSummarySection(
                title: AppStrings.attendanceFieldCheckOutTime,
                rows: [
                  ReviewDetailRow(
                    'Time',
                    entry.outTime != null
                        ? _formatDateTime(entry.outTime!)
                        : AppStrings.attendanceNotCheckedOutYet,
                  ),
                  if (entry.checkOutAttendanceType != null)
                    ReviewDetailRow(
                      AppStrings.attendanceFieldWorkMode,
                      AttendanceTypeX.fromApiValue(entry.checkOutAttendanceType).label,
                    ),
                  ReviewDetailRow(
                    AppStrings.attendanceFieldCheckOutLocation,
                    _formatLocation(
                      entry.checkOutLocationName,
                      entry.checkOutLatitude,
                      entry.checkOutLongitude,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
