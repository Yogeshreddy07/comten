import 'package:flutter/material.dart';

/// Work mode selected by the employee at check-in - mirrors the backend's
/// `com.comten.enums.AttendanceType` exactly (see
/// `AttendanceServiceImpl#checkIn`). Not a check-in/check-out event type -
/// both are represented on the same row via `Attendance.inTime`/`outTime`.
enum AttendanceType {
  atOffice,
  atSite,
}

extension AttendanceTypeX on AttendanceType {
  String get label {
    switch (this) {
      case AttendanceType.atOffice:
        return 'At Office';
      case AttendanceType.atSite:
        return 'At Site';
    }
  }

  String get apiValue {
    switch (this) {
      case AttendanceType.atOffice:
        return 'AT_OFFICE';
      case AttendanceType.atSite:
        return 'AT_SITE';
    }
  }

  IconData get icon {
    switch (this) {
      case AttendanceType.atOffice:
        return Icons.apartment_outlined;
      case AttendanceType.atSite:
        return Icons.location_on_outlined;
    }
  }

  static AttendanceType fromApiValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'AT_SITE':
        return AttendanceType.atSite;
      default:
        return AttendanceType.atOffice;
    }
  }
}
