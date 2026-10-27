/// Request body for `POST /api/attendance/check-in` - mirrors the backend's
/// `CheckInRequest` exactly.
class CheckInRequest {
  final String attendanceType;
  final double latitude;
  final double longitude;

  /// Reverse-geocoded address for [latitude]/[longitude]; omitted when the
  /// device couldn't resolve one.
  final String? locationName;

  const CheckInRequest({
    required this.attendanceType,
    required this.latitude,
    required this.longitude,
    this.locationName,
  });

  Map<String, dynamic> toJson() {
    return {
      'attendanceType': attendanceType,
      'latitude': latitude,
      'longitude': longitude,
      if (locationName != null) 'locationName': locationName,
    };
  }
}
