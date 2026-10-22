import '../../../shared/enums/team_attendance_status.dart';

/// One team member's attendance for a single requested date - mirrors the
/// backend's `TeamAttendanceResponse` exactly (see `GET /api/attendance/
/// team?date=`). Returned for every member of a project the Team Lead
/// leads, even those with no attendance row for that date (every
/// attendance-specific field is then null and [status] is
/// [TeamAttendanceStatus.notCheckedIn]).
class TeamAttendanceEntry {
  final int employeeId;
  final String employeeCode;
  final String employeeName;

  final DateTime attendanceDate;
  final String status;

  final String? attendanceType;
  final String? checkOutAttendanceType;
  final DateTime? inTime;
  final DateTime? outTime;

  final double? latitude;
  final double? longitude;
  final double? checkOutLatitude;
  final double? checkOutLongitude;

  final String? locationName;
  final String? checkOutLocationName;

  const TeamAttendanceEntry({
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.attendanceDate,
    required this.status,
    this.attendanceType,
    this.checkOutAttendanceType,
    this.inTime,
    this.outTime,
    this.latitude,
    this.longitude,
    this.checkOutLatitude,
    this.checkOutLongitude,
    this.locationName,
    this.checkOutLocationName,
  });

  TeamAttendanceStatus get effectiveStatus =>
      TeamAttendanceStatusX.fromApiValue(status);

  bool get hasAttendanceRecord =>
      effectiveStatus != TeamAttendanceStatus.notCheckedIn;

  factory TeamAttendanceEntry.fromJson(Map<String, dynamic> json) {
    return TeamAttendanceEntry(
      employeeId: json['employeeId'] as int,
      employeeCode: json['employeeCode'] as String? ?? '',
      employeeName: json['employeeName'] as String? ?? '',
      attendanceDate: DateTime.parse(json['attendanceDate'] as String),
      status: json['status'] as String? ?? '',
      attendanceType: json['attendanceType'] as String?,
      checkOutAttendanceType: json['checkOutAttendanceType'] as String?,
      inTime: json['inTime'] != null
          ? DateTime.parse(json['inTime'] as String).toLocal()
          : null,
      outTime: json['outTime'] != null
          ? DateTime.parse(json['outTime'] as String).toLocal()
          : null,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      checkOutLatitude: (json['checkOutLatitude'] as num?)?.toDouble(),
      checkOutLongitude: (json['checkOutLongitude'] as num?)?.toDouble(),
      locationName: json['locationName'] as String?,
      checkOutLocationName: json['checkOutLocationName'] as String?,
    );
  }
}
