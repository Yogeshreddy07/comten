/// Request payload for `POST /api/modules` - adds a module to an existing
/// project. Mirrors the backend's `CreateModuleRequest` field-for-field.
class CreateModuleRequest {
  final int projectId;
  final String moduleName;
  final int? teamLeadId;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? estimatedMinutes;
  final List<int> memberIds;
  final List<int> billableActivityIds;
  final List<int> nonBillableActivityIds;
  final String buildingClassification;
  final String structureClassification;
  final int numberOfFloors;
  final double area;

  const CreateModuleRequest({
    required this.projectId,
    required this.moduleName,
    this.teamLeadId,
    this.startDate,
    this.endDate,
    this.estimatedMinutes,
    this.memberIds = const [],
    this.billableActivityIds = const [],
    this.nonBillableActivityIds = const [],
    required this.buildingClassification,
    required this.structureClassification,
    required this.numberOfFloors,
    required this.area,
  });

  static String _isoDate(DateTime date) => date.toIso8601String().substring(0, 10);

  Map<String, dynamic> toJson() {
    return {
      'projectId': projectId,
      'moduleName': moduleName,
      if (teamLeadId != null) 'teamLeadId': teamLeadId,
      if (startDate != null) 'startDate': _isoDate(startDate!),
      if (endDate != null) 'endDate': _isoDate(endDate!),
      if (estimatedMinutes != null) 'estimatedMinutes': estimatedMinutes,
      'memberIds': memberIds,
      'billableActivityIds': billableActivityIds,
      'nonBillableActivityIds': nonBillableActivityIds,
      'buildingClassification': buildingClassification,
      'structureClassification': structureClassification,
      'numberOfFloors': numberOfFloors,
      'area': area,
    };
  }
}
