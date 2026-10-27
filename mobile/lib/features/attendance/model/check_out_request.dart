/// Request body for `PUT /api/attendance/check-out` - mirrors the backend's
/// `CheckOutRequest` exactly.
class CheckOutRequest {
  final String attendanceType;
  final double latitude;
  final double longitude;

  /// Reverse-geocoded address for [latitude]/[longitude]; omitted when the
  /// device couldn't resolve one.
  final String? locationName;

  const CheckOutRequest({
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
