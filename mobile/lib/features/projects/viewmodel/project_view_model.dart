import '../../../core/services/performance_trace.dart';
import 'dart:async';

import '../../../shared/enums/project_status.dart';
import '../../auth/model/api_result.dart';
import '../model/project_list_item.dart';
import '../model/project_summary.dart';
import '../model/update_project_request.dart';
import '../repository/project_repository.dart';

enum ProjectLoadState { initial, loading, success, error }

class ProjectViewModel extends PerformanceNotifier {
  final ProjectRepository _repository;
  int _generation = 0;

  ProjectViewModel({required ProjectRepository repository})
      : _repository = repository { _repository.addCacheListener(_onCacheContextChanged); }
  void _onCacheContextChanged() {
    _projects = []; _workLogProjects = []; _selectedProject = null;
    final state = _repository.cacheAuthorized ? ProjectLoadState.initial : ProjectLoadState.error;
    _loadState = state; _workLogLoadState = state; _detailState = state;
    if (state == ProjectLoadState.error) {
      _errorMessage = 'Project cache access ended. Refresh while online.';
      _workLogErrorMessage = _errorMessage; _detailErrorMessage = _errorMessage;
    }
    notifyListeners();
  }
  @override
  void dispose() { _repository.removeCacheListener(_onCacheContextChanged); super.dispose(); }

  // ---- List (GET /projects) ----
  ProjectLoadState _loadState = ProjectLoadState.initial;
  List<ProjectListItem> _projects = [];
  String? _errorMessage;

  ProjectLoadState get loadState => _loadState;
  List<ProjectListItem> get projects => _projects;
  String? get errorMessage => _errorMessage;
  bool get cacheReadsEnabled => _repository.cacheEnabled;

  /// Fetches every project (active and inactive - the Projects view is a
  /// single flat list, not separate tabs) and sorts it by computed status:
  /// In Progress -> Not Started -> Completed -> Inactive (bottom), tying
  /// within a bucket by project name so the order stays stable.
  Future<void> fetchProjects({bool force = false}) async {
    final generation = _generation;
    final cached = _repository.peekProjects() as List<ProjectListItem>?;
    if (cached != null) _projects = cached;
    _loadState = cached == null ? ProjectLoadState.loading : ProjectLoadState.success;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getProjects(force: force);
    if (generation != _generation) return;

    if (result.success) {
      final projects = (result.data as List<ProjectListItem>?) ?? [];
      projects.sort((a, b) {
        final priorityCompare = ProjectStatusX.fromApiValue(a.status)
            .projectSortPriority
            .compareTo(ProjectStatusX.fromApiValue(b.status).projectSortPriority);
        if (priorityCompare != 0) return priorityCompare;
        return a.projectName.toLowerCase().compareTo(b.projectName.toLowerCase());
      });
      _projects = projects;
      _loadState = ProjectLoadState.success;
    } else {
      if (_repository.cacheEnabled) _projects = [];
      _errorMessage = result.message;
      _loadState = ProjectLoadState.error;
    }

    notifyListeners();
  }

  // ---- Work Log-eligible list (GET /projects?hasInProgressModule=true) - a
  // separate cache from [projects] above, even though both come from the
  // same endpoint on this same shared, app-wide instance: [SubmitTimesheetScreen]
  // must not overwrite what [ProjectListScreen] already loaded (or vice
  // versa), since each expects a differently-scoped list. ----
  ProjectLoadState _workLogLoadState = ProjectLoadState.initial;
  List<ProjectListItem> _workLogProjects = [];
  String? _workLogErrorMessage;

  ProjectLoadState get workLogLoadState => _workLogLoadState;
  List<ProjectListItem> get workLogProjects => _workLogProjects;
  String? get workLogErrorMessage => _workLogErrorMessage;

  /// Projects eligible for the Work Log form: the current employee has at
  /// least one of their own modules In Progress on the project (see
  /// `ProjectServiceImpl#getProjects` - a project isn't offered just because
  /// *some* module of theirs exists on it, since hours can only ever be
  /// logged against an In Progress module, per
  /// `WorkLogServiceImpl#submitWorkLog`).
  Future<void> fetchWorkLogProjects() async {
    final generation = _generation;
    final cached = _repository.peekProjects(hasInProgressModule: true) as List<ProjectListItem>?;
    if (cached != null) _workLogProjects = cached;
    _workLogLoadState = cached == null ? ProjectLoadState.loading : ProjectLoadState.success;
    _workLogErrorMessage = null;
    notifyListeners();

    final result = await _repository.getProjects(hasInProgressModule: true);
    if (generation != _generation) return;

    if (result.success) {
      final projects = (result.data as List<ProjectListItem>?) ?? [];
      projects.sort(
          (a, b) => a.projectName.toLowerCase().compareTo(b.projectName.toLowerCase()));
      _workLogProjects = projects;
      _workLogLoadState = ProjectLoadState.success;
    } else {
      if (_repository.cacheEnabled) _workLogProjects = [];
      _workLogErrorMessage = result.message;
      _workLogLoadState = ProjectLoadState.error;
    }

    notifyListeners();
  }

  // ---- Detail (GET /projects/{id}) - one active detail at a time, matching
  // there only ever being one Details screen visible in the stack. ----
  ProjectLoadState _detailState = ProjectLoadState.initial;
  ProjectSummary? _selectedProject;
  String? _detailErrorMessage;

  ProjectLoadState get detailState => _detailState;
  ProjectSummary? get selectedProject => _selectedProject;
  String? get detailErrorMessage => _detailErrorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _generation++;
    unawaited(_repository.clearReadCache());
    _loadState = ProjectLoadState.initial;
    _projects = [];
    _errorMessage = null;
    _workLogLoadState = ProjectLoadState.initial;
    _workLogProjects = [];
    _workLogErrorMessage = null;
    _detailState = ProjectLoadState.initial;
    _selectedProject = null;
    _detailErrorMessage = null;
    _isSaving = false;
    _isDeactivating = false;
    notifyListeners();
  }

  Future<void> fetchProjectDetails(int id, {bool force = false}) async {
    final generation = _generation;
    final cached = _repository.peekDetails(id);
    if (cached != null) _selectedProject = cached;
    _detailState = cached == null ? ProjectLoadState.loading : ProjectLoadState.success;
    _detailErrorMessage = null;
    notifyListeners();

    final result = await _repository.getProjectDetails(id, force: force);
    if (generation != _generation) return;

    if (result.success) {
      _selectedProject = result.data as ProjectSummary?;
      _detailState = ProjectLoadState.success;
    } else {
      if (_repository.cacheEnabled) _selectedProject = null;
      _detailErrorMessage = result.message;
      _detailState = ProjectLoadState.error;
    }

    notifyListeners();
  }

  // ---- Mutations ----
  bool _isSaving = false;
  bool _isDeactivating = false;

  bool get isSaving => _isSaving;
  bool get isDeactivating => _isDeactivating;

  Future<ApiResult> updateProject(int id, UpdateProjectRequest request) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.updateProject(id, request);

    if (result.success) {
      final updated = result.data as ProjectSummary?;
      if (updated != null) {
        _selectedProject = updated;
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }

  /// Apply the confirmed server state without waiting for a full list reload.
  /// A billing approval request leaves the project active.
  Future<ApiResult> deactivateProject(int id) async {
    _isDeactivating = true;
    notifyListeners();

    final result = await _repository.deactivateProject(id);

    if (result.success && result.data is Map &&
        (result.data as Map)['active'] == false) {
      _applyProjectState(id, active: false);
    }

    _isDeactivating = false;
    notifyListeners();
    return result;
  }

  /// Reactivates a previously deactivated project (backend sets `isActive`
  /// to true; does not cascade to modules - each stays Inactive until
  /// activated individually). Refetches so the row re-sorts by its
  /// (unchanged) module-derived status.
  Future<ApiResult> activateProject(int id) async {
    _isDeactivating = true;
    notifyListeners();

    final result = await _repository.activateProject(id);

    if (result.success) {
      _applyProjectState(id, active: true);
    }

    _isDeactivating = false;
    notifyListeners();
    return result;
  }

  void _applyProjectState(int id, {required bool active}) {
    // Project activation keeps every child inactive.
    _projects = _projects.map((p) => p.id == id
        ? p.copyWith(isActive: active,
            status: active ? 'NOT_STARTED' : 'INACTIVE', moduleCount: 0)
        : p).toList();
    _projects.sort((a, b) {
      final priority = ProjectStatusX.fromApiValue(a.status).projectSortPriority
          .compareTo(ProjectStatusX.fromApiValue(b.status).projectSortPriority);
      return priority != 0 ? priority
          : a.projectName.toLowerCase().compareTo(b.projectName.toLowerCase());
    });
    _workLogProjects = _workLogProjects.where((p) => p.id != id).toList();
  }

  /// Soft-deletes the project (backend sets `isDeleted` to true; the row
  /// and its modules are retained for records but excluded from every
  /// future list response) - removed from the local list immediately.
  Future<ApiResult> deleteProject(int id) async {
    _isDeactivating = true;
    notifyListeners();

    final result = await _repository.deleteProject(id);

    if (result.success) {
      _projects = _projects.where((p) => p.id != id).toList();
    }

    _isDeactivating = false;
    notifyListeners();
    return result;
  }
}
