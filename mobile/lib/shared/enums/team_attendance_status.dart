import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Mirrors the backend's derived status on `TeamAttendanceResponse` exactly
/// (see `AttendanceMapper#toTeamResponse`) - `NOT_CHECKED_IN` covers every
/// team member with no attendance row for the requested date, so the Team
/// Attendance screen can show the full roster rather than only employees
/// who happened to check in.
enum TeamAttendanceStatus {
  notCheckedIn,
  checkedIn,
  checkedOut,
}

extension TeamAttendanceStatusX on TeamAttendanceStatus {
  String get label {
    switch (this) {
      case TeamAttendanceStatus.notCheckedIn:
        return 'Not Checked In';
      case TeamAttendanceStatus.checkedIn:
        return 'Checked In';
      case TeamAttendanceStatus.checkedOut:
        return 'Checked Out';
    }
  }

  Color get color {
    switch (this) {
      case TeamAttendanceStatus.notCheckedIn:
        return AppColors.statusNotStarted;
      case TeamAttendanceStatus.checkedIn:
        return AppColors.statusOnHold;
      case TeamAttendanceStatus.checkedOut:
        return AppColors.statusActive;
    }
  }

  static TeamAttendanceStatus fromApiValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'CHECKED_IN':
        return TeamAttendanceStatus.checkedIn;
      case 'CHECKED_OUT':
        return TeamAttendanceStatus.checkedOut;
      default:
        return TeamAttendanceStatus.notCheckedIn;
    }
  }
}
