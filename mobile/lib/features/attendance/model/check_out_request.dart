/// Request body for `PUT /api/attendance/check-out` - mirrors the backend's
/// `CheckOutRequest` exactly.
class CheckOutRequest {
  final String attendanceType;
  final double latitude;
  final double longitude;

  const CheckOutRequest({
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
