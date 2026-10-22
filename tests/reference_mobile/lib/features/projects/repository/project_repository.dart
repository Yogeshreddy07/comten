import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/utils/preference_util.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../../../shared/enums/user_role.dart';
import '../../auth/model/api_result.dart';
import '../model/create_project_request.dart';
import '../model/project_list_item.dart';
import '../model/project_member_option.dart';
import '../model/project_summary.dart';
import '../model/update_project_request.dart';
import '../service/project_api_service.dart';
import 'project_read_cache.dart';

class ProjectRepository {
  final ProjectReadCache? _readCache;
  ProjectRepository({ProjectReadCache? syntheticReadCache}) : _readCache = syntheticReadCache;
  bool get cacheEnabled => const bool.fromEnvironment('COMTEN_SYNTHETIC_PROJECT_CACHE') && _readCache != null;
  bool get cacheAuthorized => cacheEnabled && _readCache!.authorized;
  void addCacheListener(void Function() listener) { if (cacheEnabled) _readCache!.addListener(listener); }
  void removeCacheListener(void Function() listener) { if (cacheEnabled) _readCache!.removeListener(listener); }
  dynamic peekProjects({bool? active, bool? hasInProgressModule}) {
    if (!cacheEnabled) return null;
    final data = _readCache!.peek(ProjectReadCache.listKey(active: active, inProgress: hasInProgressModule));
    try { return (data as List?)?.map((x) => ProjectListItem.fromJson(Map<String, dynamic>.from(x))).toList(); }
    catch (_) { return null; }
  }
  ProjectSummary? peekDetails(int id) {
    if (!cacheEnabled) return null;
    final data = _readCache!.peek('detail:$id');
    try { return data == null ? null : ProjectSummary.fromJson(Map<String, dynamic>.from(data)); }
    catch (_) { return null; }
  }
  Future<ApiResult> _cached(String key, dynamic Function(dynamic) mapData, bool force) async {
    try { return ApiResult(success: true, message: 'Projects loaded successfully', data: mapData(await _readCache!.read(key, force: force))); }
    on ProjectCacheException catch (e) { return ApiResult(success: false, message: e.message); }
    catch (_) { return ApiResult(success: false, message: 'Unable to load project data.'); }
  }
  Future<void> clearReadCache() async { if (cacheEnabled) await _readCache!.logout(); }
  Future<void> invalidateReadCache() async { if (cacheEnabled) await _readCache!.invalidate(); }
  final ProjectApiService _apiService = ProjectApiService();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// The stored JWT for whichever employee is currently signed in - needed
  /// because `/api/projects/**` requires `Authentication` on the backend
  /// (see `SecurityConfig`: `.anyRequest().authenticated()`).
  Future<String?> _currentToken() async {
    final employeeCode = await _secureStorage.getActiveEmployeeCode();
    if (employeeCode == null || employeeCode.isEmpty) return null;
    return PreferenceUtil.getJwtToken(employeeCode);
  }

  /// Shared request-and-decode path used by every method below. [isSuccess]
  /// preserves each endpoint's own status-code contract; [mapData] converts
  /// the raw `data` payload into a domain model only when the request
  /// succeeded.
  Future<ApiResult> _request(
    Future<http.Response> Function() call, {
    required bool Function(int statusCode) isSuccess,
    dynamic Function(dynamic data)? mapData,
    String successMessage = "Success",
  }) async {
    try {
      final response = await call();
      final success = isSuccess(response.statusCode);

      if (response.body.isEmpty) {
        return ApiResult(
          success: success,
          message: success ? successMessage : "Server returned ${response.statusCode}",
        );
      }

      final body = jsonDecode(response.body);
      final rawData = body["data"];

      return ApiResult(
        success: success,
        message: body["message"] ?? (success ? successMessage : "Unknown error"),
        data: success && rawData != null && mapData != null
            ? mapData(rawData)
            : (success ? rawData : null),
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: "Unable to connect to server.",
      );
    }
  }

  /// `GET /projects` - list rows for [ProjectListScreen]. Pass [active] to
  /// scope to only active or only inactive (deactivated) projects; omit for
  /// both. Pass [hasInProgressModule] = true to further scope to projects
  /// where the current user has at least one In Progress module of their
  /// own (see [ProjectViewModel.fetchWorkLogProjects]). Deleted projects are
  /// always excluded by the backend.
  Future<ApiResult> getProjects({bool? active, bool? hasInProgressModule, bool force = false}) async {
    if (cacheEnabled) {
      return _cached(ProjectReadCache.listKey(active: active, inProgress: hasInProgressModule),
        (data) => (data as List).map((x) => ProjectListItem.fromJson(Map<String, dynamic>.from(x))).toList(), force);
    }
    final token = await _currentToken();
    return _request(
      () => _apiService.getProjects(
        token: token,
        active: active,
        hasInProgressModule: hasInProgressModule,
      ),
      isSuccess: (code) => code == 200,
      successMessage: "Projects loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => ProjectListItem.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `GET /projects/{id}` - full detail (project + nested modules) for
  /// [ProjectDetailsScreen].
  Future<ApiResult> getProjectDetails(int id, {bool force = false}) async {
    if (cacheEnabled) return _cached('detail:$id', (data) => ProjectSummary.fromJson(Map<String, dynamic>.from(data)), force);
    final token = await _currentToken();
    return _request(
      () => _apiService.getProjectById(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Project details loaded successfully",
      mapData: (data) => ProjectSummary.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Creates a project together with its first module (`POST /projects`).
  Future<ApiResult> submitProject(CreateProjectRequest request) async {
    if (cacheEnabled) return ApiResult(success: false, message: 'Synthetic project cache is read-only.');
    final token = await _currentToken();
    return _request(
      () => _apiService.createProject(request.toJson(), token: token),
      isSuccess: (code) => code == 200 || code == 201,
      mapData: (data) => ProjectSummary.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /projects/{id}` - used by [EditProjectScreen]. Project-level
  /// fields only now (name/client).
  Future<ApiResult> updateProject(int id, UpdateProjectRequest request) async {
    if (cacheEnabled) return ApiResult(success: false, message: 'Synthetic project cache is read-only.');
    final token = await _currentToken();
    return _request(
      () => _apiService.updateProject(id.toString(), request.toJson(), token: token),
      isSuccess: (code) => code == 200,
      mapData: (data) => ProjectSummary.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `DELETE /projects/{id}` - soft-deactivates the project (backend sets
  /// `isActive` to false and cascades to every one of its modules).
  Future<ApiResult> deactivateProject(int id) async {
    if (cacheEnabled) return ApiResult(success: false, message: 'Synthetic project cache is read-only.');
    final token = await _currentToken();
    return _request(
      () => _apiService.deactivateProject(id.toString(), token: token),
      isSuccess: (code) => code == 200 || code == 204,
      successMessage: "Project has been successfully deactivated.",
    );
  }

  /// `PUT /projects/{id}/activate` - reactivates a previously deactivated
  /// project (backend sets `isActive` to true; does not cascade to modules).
  Future<ApiResult> activateProject(int id) async {
    if (cacheEnabled) return ApiResult(success: false, message: 'Synthetic project cache is read-only.');
    final token = await _currentToken();
    return _request(
      () => _apiService.activateProject(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Project has been successfully activated.",
    );
  }

  /// `PUT /projects/{id}/delete` - soft-deletes the project (backend sets
  /// `isDeleted` to true; the row and its modules are retained for records
  /// but the project never appears in any future list response).
  Future<ApiResult> deleteProject(int id) async {
    if (cacheEnabled) return ApiResult(success: false, message: 'Synthetic project cache is read-only.');
    final token = await _currentToken();
    return _request(
      () => _apiService.deleteProject(id.toString(), token: token),
      isSuccess: (code) => code == 200 || code == 204,
      successMessage: "Project deleted successfully",
    );
  }

  /// Users belonging to [role] - used to populate the Team Leader and Team
  /// Members pickers on the Create/Edit Project/Module screens (`GET
  /// /projects/users`).
  Future<ApiResult> getUsersByRole(UserRole role) async {
    if (cacheEnabled) return ApiResult(success: false, message: 'Synthetic project cache is read-only.');
    final token = await _currentToken();
    return _request(
      () => _apiService.getUsersByRole(role.backendValue, token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Users loaded successfully",
      mapData: (data) => (data as List)
          .map((json) =>
              ProjectMemberOption.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }
}
