/// Request payload for `PUT /api/projects/{id}` - mirrors the backend's
/// `UpdateProjectRequest` field-for-field. Project-level fields only now
/// (Team Lead, team, timeline, hours, status all moved to Module - see
/// `features/modules/model/update_module_request.dart`).
class UpdateProjectRequest {
  final String? projectName;
  final String? clientId;

  const UpdateProjectRequest({
    this.projectName,
    this.clientId,
  });

  Map<String, dynamic> toJson() {
    return {
      if (projectName != null) 'projectName': projectName,
      if (clientId != null) 'clientId': clientId,
    };
  }
}
