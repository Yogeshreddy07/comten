import '../../../core/services/performance_trace.dart';

import '../../../shared/enums/user_role.dart';
import '../../activities/model/activity.dart';
import '../../auth/model/api_result.dart';
import '../../modules/model/create_module_request.dart';
import '../../modules/model/module_summary.dart';
import '../../modules/repository/module_repository.dart';
import '../../modules/utils/module_validator.dart';
import '../model/create_project_request.dart';
import '../model/project_list_item.dart';
import '../model/project_member_option.dart';
import '../model/project_summary.dart';
import '../repository/project_repository.dart';
import '../utils/project_validator.dart';

/// Owns the Create Project/Module wizard's state across the Create -> Review
/// -> Success screens (all three share one instance, scoped by the screen
/// that starts the flow), so "Edit" naturally preserves everything the user
/// already entered without any manual re-hydration.
///
/// A project is never created alone - it always comes with its first module.
/// [isNewProject] toggles which "parent" path is taken: creating a brand new
/// project (Project Information fields required) or adding a module to an
/// [existingProject] chosen from a dropdown. Either way, the Module section
/// (Module Name, Team Leader, Employees, Activities, Timeline, Estimated
/// Hours) is always collected.
///
/// Team assignment is a strict hierarchy: Team Leader -> Employees. The
/// backend has no org-chart relationship linking these roles together
/// (`UserRepository` only supports filtering by role, not by "reports to"),
/// so each level's picker loads *all* users of that role via the existing
/// `GET /projects/users?role=` endpoint rather than a truly filtered
/// subset. Selecting a parent still clears whatever was chosen at the
/// level(s) below it, matching the required UX even though the returned
/// list itself isn't parent-scoped yet.
class CreateProjectViewModel extends PerformanceNotifier {
  final ProjectRepository _projectRepository;
  final ModuleRepository _moduleRepository;

  CreateProjectViewModel({
    required ProjectRepository projectRepository,
    required ModuleRepository moduleRepository,
  })  : _projectRepository = projectRepository,
        _moduleRepository = moduleRepository;

  // ---- New vs Existing project choice ----
  bool _isNewProject = true;
  bool get isNewProject => _isNewProject;

  void setIsNewProject(bool value) {
    _isNewProject = value;
    if (value) {
      _existingProject = null;
    }
    notifyListeners();
  }

  // ---- New-project fields ----
  String _clientId = '';
  String _projectName = '';
  String _projectCode = '';

  String get clientId => _clientId;
  String get projectName => _projectName;
  String get projectCode => _projectCode;

  void setClientId(String value) => _clientId = value;
  void setProjectName(String value) => _projectName = value;
  void setProjectCode(String value) => _projectCode = value;

  // ---- Existing-project selection ----
  ProjectListItem? _existingProject;
  ProjectListItem? get existingProject => _existingProject;

  void setExistingProject(ProjectListItem? value) {
    _existingProject = value;
    notifyListeners();
  }

  bool _isLoadingProjects = false;
  String? _projectsError;
  List<ProjectListItem> _existingProjects = [];

  bool get isLoadingProjects => _isLoadingProjects;
  String? get projectsError => _projectsError;
  List<ProjectListItem> get existingProjects => _existingProjects;

  Future<void> loadExistingProjects({bool forceRefresh = false}) async {
    if (!forceRefresh && _existingProjects.isNotEmpty) return;

    _isLoadingProjects = true;
    _projectsError = null;
    notifyListeners();

    // Only active projects: a deactivated project can no longer have new
    // modules created inside it (backend now rejects it too), so it
    // shouldn't be offered as an "add module to existing project" target.
    final result = await _projectRepository.getProjects(active: true);

    if (result.success) {
      _existingProjects = (result.data as List<ProjectListItem>?) ?? [];
    } else {
      _projectsError = result.message;
    }

    _isLoadingProjects = false;
    notifyListeners();
  }

  // ---- Module fields ----
  String _moduleName = '';
  String _buildingClassification = '';
  String _structureClassification = '';
  String _numberOfFloorsText = '';
  String _areaText = '';
  String _hoursText = '';
  String _minutesText = '';
  String _secondsText = '';
  DateTime? _startDate;
  DateTime? _endDate;
  ProjectMemberOption? _teamLeader;
  final List<ProjectMemberOption> _selectedEmployees = [];
  final List<Activity> _selectedBillableActivities = [];
  final List<Activity> _selectedNonBillableActivities = [];

  String get moduleName => _moduleName;
  String get buildingClassification => _buildingClassification;
  String get structureClassification => _structureClassification;
  String get numberOfFloorsText => _numberOfFloorsText;
  String get areaText => _areaText;
  String get hoursText => _hoursText;
  String get minutesText => _minutesText;
  String get secondsText => _secondsText;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  ProjectMemberOption? get teamLeader => _teamLeader;
  List<ProjectMemberOption> get selectedEmployees =>
      List.unmodifiable(_selectedEmployees);
  List<Activity> get selectedBillableActivities =>
      List.unmodifiable(_selectedBillableActivities);
  List<Activity> get selectedNonBillableActivities =>
      List.unmodifiable(_selectedNonBillableActivities);

  void setModuleName(String value) => _moduleName = value;
  void setBuildingClassification(String value) => _buildingClassification = value;
  void setStructureClassification(String value) => _structureClassification = value;
  void setNumberOfFloorsText(String value) => _numberOfFloorsText = value;
  void setAreaText(String value) => _areaText = value;
  void setHoursText(String value) => _hoursText = value;
  void setMinutesText(String value) => _minutesText = value;
  void setSecondsText(String value) => _secondsText = value;

  void setStartDate(DateTime value) {
    _startDate = value;
    // An already-picked end date earlier than the new start date is no
    // longer valid - clear it instead of silently submitting a bad range.
    if (_endDate != null && _endDate!.isBefore(value)) {
      _endDate = null;
    }
    notifyListeners();
  }

  void setEndDate(DateTime value) {
    _endDate = value;
    notifyListeners();
  }

  void setTeamLeader(ProjectMemberOption? value) {
    _teamLeader = value;
    _selectedEmployees.clear();
    notifyListeners();
  }

  bool isEmployeeSelected(ProjectMemberOption user) =>
      _selectedEmployees.contains(user);

  void toggleEmployee(ProjectMemberOption user) {
    if (_selectedEmployees.contains(user)) {
      _selectedEmployees.remove(user);
    } else {
      _selectedEmployees.add(user);
    }
    notifyListeners();
  }

  /// The same activity may be toggled independently in both categories -
  /// see [selectedBillableActivities]/[selectedNonBillableActivities].
  void toggleBillableActivity(Activity activity) {
    if (_selectedBillableActivities.contains(activity)) {
      _selectedBillableActivities.remove(activity);
    } else {
      _selectedBillableActivities.add(activity);
    }
    notifyListeners();
  }

  void toggleNonBillableActivity(Activity activity) {
    if (_selectedNonBillableActivities.contains(activity)) {
      _selectedNonBillableActivities.remove(activity);
    } else {
      _selectedNonBillableActivities.add(activity);
    }
    notifyListeners();
  }

  // ---- Per-role user lookup (Team Leader / Employees pickers) ----
  final Map<UserRole, List<ProjectMemberOption>> _usersByRole = {};
  final Map<UserRole, bool> _loadingByRole = {};
  final Map<UserRole, String?> _errorByRole = {};

  List<ProjectMemberOption> usersFor(UserRole role) =>
      _usersByRole[role] ?? const [];

  bool isLoadingUsersFor(UserRole role) => _loadingByRole[role] ?? false;

  String? usersErrorFor(UserRole role) => _errorByRole[role];

  Future<void> loadUsersForRole(UserRole role, {bool forceRefresh = false}) async {
    if (!forceRefresh && _usersByRole.containsKey(role)) return;

    _loadingByRole[role] = true;
    _errorByRole[role] = null;
    notifyListeners();

    final result = await _projectRepository.getUsersByRole(role);

    if (result.success) {
      _usersByRole[role] = (result.data as List<ProjectMemberOption>?) ?? [];
    } else {
      _errorByRole[role] = result.message;
    }

    _loadingByRole[role] = false;
    notifyListeners();
  }

  // ---- Validation ----
  final Map<String, String> _fieldErrors = {};
  Map<String, String> get fieldErrors => Map.unmodifiable(_fieldErrors);

  /// Total estimated minutes represented by the Hours/Minutes/Seconds boxes -
  /// reuses [ModuleValidator.durationBoxesToMinutes] so Create Project and
  /// Edit Module's Additional Working Hours convert H:M:S the same way.
  /// Returns null if any of the three fields isn't a valid non-negative
  /// number.
  int? get totalEstimatedMinutes => ModuleValidator.durationBoxesToMinutes(
        _hoursText,
        _minutesText,
        _secondsText,
      );

  bool validate() {
    _fieldErrors.clear();

    if (_isNewProject) {
      final nameError = ProjectValidator.projectName(_projectName);
      if (nameError != null) _fieldErrors['projectName'] = nameError;

      final codeError = ProjectValidator.projectCode(_projectCode);
      if (codeError != null) _fieldErrors['projectCode'] = codeError;
    } else {
      final projectError = ProjectValidator.existingProject(_existingProject?.id);
      if (projectError != null) _fieldErrors['existingProject'] = projectError;
    }

    final moduleNameError = ModuleValidator.moduleName(_moduleName);
    if (moduleNameError != null) _fieldErrors['moduleName'] = moduleNameError;

    final buildingClassificationError =
        ModuleValidator.buildingClassification(_buildingClassification);
    if (buildingClassificationError != null) {
      _fieldErrors['buildingClassification'] = buildingClassificationError;
    }

    final structureClassificationError =
        ModuleValidator.structureClassification(_structureClassification);
    if (structureClassificationError != null) {
      _fieldErrors['structureClassification'] = structureClassificationError;
    }

    final numberOfFloorsError = ModuleValidator.numberOfFloors(_numberOfFloorsText);
    if (numberOfFloorsError != null) _fieldErrors['numberOfFloors'] = numberOfFloorsError;

    final areaError = ModuleValidator.area(_areaText);
    if (areaError != null) _fieldErrors['area'] = areaError;

    final hoursError = ModuleValidator.durationField(_hoursText, 'Hours');
    if (hoursError != null) _fieldErrors['hours'] = hoursError;

    final minutesError = ModuleValidator.minutesOrSeconds(_minutesText, 'Minutes');
    if (minutesError != null) _fieldErrors['minutes'] = minutesError;

    final secondsError = ModuleValidator.minutesOrSeconds(_secondsText, 'Seconds');
    if (secondsError != null) _fieldErrors['seconds'] = secondsError;

    final startError = ModuleValidator.startDate(_startDate);
    if (startError != null) _fieldErrors['startDate'] = startError;

    final endError = ModuleValidator.endDate(_endDate, _startDate);
    if (endError != null) _fieldErrors['endDate'] = endError;

    if (!_fieldErrors.containsKey('hours')) {
      final minimumHoursError = ModuleValidator.estimatedWorkingHoursMinimum(
          totalEstimatedMinutes, 'Estimated Working Hours');
      if (minimumHoursError != null) _fieldErrors['hours'] = minimumHoursError;
    }

    if (!_fieldErrors.containsKey('hours')) {
      final timelineHoursError = ModuleValidator.estimatedMinutesWithinTimeline(
        totalEstimatedMinutes,
        _startDate,
        _endDate,
      );
      if (timelineHoursError != null) _fieldErrors['hours'] = timelineHoursError;
    }

    final leaderError = ModuleValidator.teamLeader(_teamLeader);
    if (leaderError != null) _fieldErrors['teamLeader'] = leaderError;

    final employeesError = ModuleValidator.employees(_selectedEmployees);
    if (employeesError != null) _fieldErrors['employees'] = employeesError;

    final billableActivitiesError =
        ModuleValidator.billableActivities(_selectedBillableActivities);
    if (billableActivitiesError != null) {
      _fieldErrors['billableActivities'] = billableActivitiesError;
    }

    final nonBillableActivitiesError =
        ModuleValidator.nonBillableActivities(_selectedNonBillableActivities);
    if (nonBillableActivitiesError != null) {
      _fieldErrors['nonBillableActivities'] = nonBillableActivitiesError;
    }

    notifyListeners();
    return _fieldErrors.isEmpty;
  }

  // ---- Submission ----
  bool _isSubmitting = false;
  bool _submitted = false;
  String? _submitError;
  ModuleSummary? _createdModule;

  bool get isSubmitting => _isSubmitting;
  String? get submitError => _submitError;
  ModuleSummary? get createdModule => _createdModule;

  /// Client ID to show on the Success screen - not part of [ModuleSummary],
  /// so it's sourced from whichever side of the New/Existing toggle was
  /// used (the just-typed field, or the chosen project's own value).
  String get createdClientId =>
      _isNewProject ? _clientId : (_existingProject?.clientId ?? '');

  Future<bool> submit() async {
    if (_isSubmitting) return false;
    if (_submitted) return true;
    _isSubmitting = true;
    _submitError = null;
    notifyListeners();

    final result = _isNewProject ? await _submitNewProject() : await _submitToExistingProject();

    if (result.success) {
      _submitted = true;
      _createdModule = result.data as ModuleSummary?;
    } else {
      _submitError = result.message;
    }

    _isSubmitting = false;
    notifyListeners();
    return result.success;
  }

  Future<ApiResult> _submitNewProject() async {
    final request = CreateProjectRequest(
      projectCode: _projectCode.trim(),
      projectName: _projectName.trim(),
      clientId: _clientId.trim().isEmpty ? null : _clientId.trim(),
      moduleName: _moduleName.trim(),
      teamLeadId: _teamLeader?.id,
      startDate: _startDate,
      endDate: _endDate,
      estimatedMinutes: totalEstimatedMinutes,
      memberIds: _selectedEmployees.map((employee) => employee.id).toList(),
      billableActivityIds:
          _selectedBillableActivities.map((activity) => activity.id).toList(),
      nonBillableActivityIds: _selectedNonBillableActivities
          .map((activity) => activity.id)
          .toList(),
      buildingClassification: _buildingClassification.trim(),
      structureClassification: _structureClassification.trim(),
      numberOfFloors: int.parse(_numberOfFloorsText.trim()),
      area: double.parse(_areaText.trim()),
    );

    final result = await _projectRepository.submitProject(request);
    if (!result.success) return result;

    // Reuse full details in the creation response. Older servers may still
    // return only a summary, in which case retain the detail-fetch fallback.
    final project = result.data as ProjectSummary?;
    if (project == null || project.modules.isEmpty) {
      return ApiResult(success: true, message: result.message);
    }
    if (project.moduleDetails.isNotEmpty) {
      return ApiResult(success: true, message: result.message,
          data: project.moduleDetails.first);
    }
    final details = await _moduleRepository.getModuleDetails(project.modules.first.id);
    if (details.success) return details;
    // Creation was acknowledged. A secondary display read must never invite
    // the user to submit the same project again.
    final module = project.modules.first;
    return ApiResult(success: true, message: result.message, data: ModuleSummary(
      id: module.id, projectId: project.id, projectCode: project.projectCode,
      projectName: project.projectName, moduleName: module.moduleName,
      status: module.status, startDate: module.startDate, endDate: module.endDate,
      estimatedMinutes: module.estimatedMinutes,
    ));
  }

  Future<ApiResult> _submitToExistingProject() {
    final request = CreateModuleRequest(
      projectId: _existingProject!.id,
      moduleName: _moduleName.trim(),
      teamLeadId: _teamLeader?.id,
      startDate: _startDate,
      endDate: _endDate,
      estimatedMinutes: totalEstimatedMinutes,
      memberIds: _selectedEmployees.map((employee) => employee.id).toList(),
      billableActivityIds:
          _selectedBillableActivities.map((activity) => activity.id).toList(),
      nonBillableActivityIds: _selectedNonBillableActivities
          .map((activity) => activity.id)
          .toList(),
      buildingClassification: _buildingClassification.trim(),
      structureClassification: _structureClassification.trim(),
      numberOfFloors: int.parse(_numberOfFloorsText.trim()),
      area: double.parse(_areaText.trim()),
    );
    return _moduleRepository.createModule(request);
  }
}
