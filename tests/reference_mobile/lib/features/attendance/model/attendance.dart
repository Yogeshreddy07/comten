/// A single day's attendance row - mirrors the backend's
/// `AttendanceResponse` exactly (see `GET /api/attendance/today`,
/// `GET /api/attendance/team`, `POST /api/attendance/check-in`,
/// `PUT /api/attendance/check-out`).
class Attendance {
  final int id;

  final int employeeId;
  final String employeeCode;
  final String employeeName;

  final String attendanceType;
  final String? checkOutAttendanceType;
  final DateTime attendanceDate;

  final DateTime inTime;
  final DateTime? outTime;

  final double latitude;
  final double longitude;
  final double? checkOutLatitude;
  final double? checkOutLongitude;

  final String? locationName;
  final String? checkOutLocationName;

  const Attendance({
    required this.id,
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.attendanceType,
    this.checkOutAttendanceType,
    required this.attendanceDate,
    required this.inTime,
    this.outTime,
    required this.latitude,
    required this.longitude,
    this.checkOutLatitude,
    this.checkOutLongitude,
    this.locationName,
    this.checkOutLocationName,
  });

  bool get isCheckedOut => outTime != null;

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      id: json['id'] as int,
      employeeId: json['employeeId'] as int,
      employeeCode: json['employeeCode'] as String? ?? '',
      employeeName: json['employeeName'] as String? ?? '',
      attendanceType: json['attendanceType'] as String? ?? '',
      checkOutAttendanceType: json['checkOutAttendanceType'] as String?,
      attendanceDate: DateTime.parse(json['attendanceDate'] as String),
      inTime: DateTime.parse(json['inTime'] as String),
      outTime: json['outTime'] != null
          ? DateTime.parse(json['outTime'] as String)
          : null,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      checkOutLatitude: (json['checkOutLatitude'] as num?)?.toDouble(),
      checkOutLongitude: (json['checkOutLongitude'] as num?)?.toDouble(),
      locationName: json['locationName'] as String?,
      checkOutLocationName: json['checkOutLocationName'] as String?,
    );
  }
}
