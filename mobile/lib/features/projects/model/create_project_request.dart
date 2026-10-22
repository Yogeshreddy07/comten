/// Request payload for `POST /api/projects` - creates a project together
/// with its first module in one call. Mirrors the backend's
/// `CreateProjectRequest` field-for-field (everything from [moduleName]
/// down becomes that first module).
class CreateProjectRequest {
  final String projectCode;
  final String projectName;
  final String? clientId;
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

  const CreateProjectRequest({
    required this.projectCode,
    required this.projectName,
    required this.moduleName,
    this.clientId,
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
      'projectCode': projectCode,
      'projectName': projectName,
      'moduleName': moduleName,
      if (clientId != null && clientId!.isNotEmpty) 'clientId': clientId,
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
