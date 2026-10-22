/// Request body for `PUT /api/billing/{projectId}` - mirrors the backend's
/// `UpdateBillingStatusRequest` exactly.
class UpdateBillingStatusRequest {
  final String spocName;
  final String status;
  final String? remarks;

  const UpdateBillingStatusRequest({
    required this.spocName,
    required this.status,
    this.remarks,
  });

  Map<String, dynamic> toJson() {
    return {
      'spocName': spocName,
      'status': status,
      if (remarks != null && remarks!.isNotEmpty) 'remarks': remarks,
    };
  }
}
