/// Request body for `POST /api/attendance/check-in` - mirrors the backend's
/// `CheckInRequest` exactly.
class CheckInRequest {
  final String attendanceType;
  final double latitude;
  final double longitude;

  const CheckInRequest({
    required this.attendanceType,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'attendanceType': attendanceType,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
