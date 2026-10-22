/// Request payload for `PUT /api/modules/{id}` - mirrors the backend's
/// `UpdateModuleRequest` field-for-field. Every field is optional: the
/// backend only overwrites a field when its key is present in the JSON body
/// (see `ModuleServiceImpl#updateModule`'s null-checks), so omit a field
/// entirely to leave it unchanged rather than sending an explicit null.
///
/// Note: `endDate`/`estimatedMinutes` are deliberately absent - changing
/// either now requires Captain approval via `ApprovalRepository.
/// submitChangeRequest`, not this endpoint (see `features/approvals/`).
/// `completedHours` is absent too - it's always derived from approved Billable work logs
/// server-side, never settable directly (see backend `ModuleServiceImpl#updateModule`).
class UpdateModuleRequest {
  final String? moduleName;
  final int? teamLeadId;
  final String? status;
  final List<int>? memberIds;
  final List<int>? billableActivityIds;
  final List<int>? nonBillableActivityIds;
  final String? remarks;
  final String? buildingClassification;
  final String? structureClassification;
  final int? numberOfFloors;
  final double? area;

  const UpdateModuleRequest({
    this.moduleName,
    this.teamLeadId,
    this.status,
    this.memberIds,
    this.billableActivityIds,
    this.nonBillableActivityIds,
    this.remarks,
    this.buildingClassification,
    this.structureClassification,
    this.numberOfFloors,
    this.area,
  });

  Map<String, dynamic> toJson() {
    return {
      if (moduleName != null) 'moduleName': moduleName,
      if (teamLeadId != null) 'teamLeadId': teamLeadId,
      if (status != null) 'status': status,
      if (memberIds != null) 'memberIds': memberIds,
      if (billableActivityIds != null) 'billableActivityIds': billableActivityIds,
      if (nonBillableActivityIds != null) 'nonBillableActivityIds': nonBillableActivityIds,
      if (remarks != null) 'remarks': remarks,
      if (buildingClassification != null) 'buildingClassification': buildingClassification,
      if (structureClassification != null) 'structureClassification': structureClassification,
      if (numberOfFloors != null) 'numberOfFloors': numberOfFloors,
      if (area != null) 'area': area,
    };
  }
}
