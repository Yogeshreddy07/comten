import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/enums/project_status.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_date_picker.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/multi_select_chip_field.dart';
import '../../../shared/widgets/multi_select_picker_sheet.dart';
import '../../activities/model/activity.dart';
import '../../activities/viewmodel/activity_view_model.dart';
import '../../approvals/model/project_change_request.dart';
import '../../approvals/model/submit_change_request.dart';
import '../../approvals/repository/approval_repository.dart';
import '../../projects/model/project_member_option.dart';
import '../../projects/widgets/estimated_duration_input.dart';
import '../../projects/widgets/section_header.dart';
import '../../projects/widgets/team_assignment_fields.dart';
import '../../projects/widgets/user_picker_sheet.dart';
import '../model/module_summary.dart';
import '../model/update_module_request.dart';
import '../utils/module_validator.dart';
import '../viewmodel/module_view_model.dart';

/// Edit Module - reassigns the Team Leader/Employees, revises the deadline
/// and estimated hours, and optionally cancels the module (the only status
/// change this screen may make - see [_status]). Deliberately narrower than
/// the Create form: module name isn't editable here, matching
/// [EditProjectScreen]'s same treatment of project code/name.
class EditModuleScreen extends StatefulWidget {
  final int moduleId;

  const EditModuleScreen({super.key, required this.moduleId});

  @override
  State<EditModuleScreen> createState() => _EditModuleScreenState();
}

class _EditModuleScreenState extends State<EditModuleScreen> {
  final _formKey = GlobalKey<FormState>();
  final ApprovalRepository _approvalRepository = DependencyInjection.approvalRepository;

  late final TextEditingController _revisedHoursController;
  late final TextEditingController _revisedMinutesController;
  late final TextEditingController _revisedSecondsController;
  late final TextEditingController _remarksController;
  late final TextEditingController _buildingClassificationController;
  late final TextEditingController _structureClassificationController;
  late final TextEditingController _numberOfFloorsController;
  late final TextEditingController _areaController;

  DateTime? _endDate;

  /// The module's current status - display-only here. Not Started/In
  /// Progress/Completed change automatically and Inactive has its own
  /// Deactivate action on [ModuleDetailsScreen]; Cancelled (via
  /// [_cancelModule]) is the only status Module Edit may set.
  ProjectStatus _status = ProjectStatus.notStarted;
  bool _cancelModule = false;
  ProjectMemberOption? _teamLeader;
  final List<ProjectMemberOption> _selectedEmployees = [];
  final List<Activity> _selectedBillableActivities = [];
  final List<Activity> _selectedNonBillableActivities = [];

  bool _scalarFieldsInitialized = false;
  bool _teamLeaderInitialized = false;
  bool _employeesInitialized = false;
  bool _activitiesInitialized = false;
  bool _isSaving = false;

  /// Non-null once there's an existing `PENDING` change request for this
  /// module - the End Date/Estimated Hours fields are locked while one is
  /// outstanding (only one request may be in flight per module, matching
  /// the backend's guard in `ModuleChangeRequestServiceImpl#submitChangeRequest`).
  ProjectChangeRequest? _pendingChangeRequest;

  /// The loaded module, cached so the Revised Working Hours controller
  /// listeners (which fire outside the build cycle) can re-check the
  /// timeline warning below.
  ModuleSummary? _module;

  /// Whether the timeline-overflow warning has already been shown for the
  /// current overflowing value - reset once the value stops overflowing, so
  /// it can warn again if the user overflows it a second time.
  bool _timelineWarningShown = false;

  final Map<UserRole, List<ProjectMemberOption>> _usersByRole = {};
  final Map<UserRole, bool> _loadingByRole = {};
  final Map<UserRole, String?> _errorByRole = {};

  @override
  void initState() {
    super.initState();
    _revisedHoursController = TextEditingController();
    _revisedMinutesController = TextEditingController();
    _revisedSecondsController = TextEditingController();
    _revisedHoursController.addListener(_onRevisedWorkingHoursChanged);
    _revisedMinutesController.addListener(_onRevisedWorkingHoursChanged);
    _revisedSecondsController.addListener(_onRevisedWorkingHoursChanged);
    _remarksController = TextEditingController();
    _buildingClassificationController = TextEditingController();
    _structureClassificationController = TextEditingController();
    _numberOfFloorsController = TextEditingController();
    _areaController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ModuleViewModel>().fetchModuleDetails(widget.moduleId);
      _loadUsersForRole(UserRole.teamLeader);
      _loadUsersForRole(UserRole.employee);
      final activityViewModel = context.read<ActivityViewModel>();
      if (activityViewModel.loadState == ActivityLoadState.initial) {
        activityViewModel.fetchActivities();
      }
      _loadPendingChangeRequest();
    });
  }

  Future<void> _loadPendingChangeRequest() async {
    final result = await _approvalRepository.getChangeRequestsForModule(widget.moduleId);
    if (!mounted || !result.success) return;
    final requests = (result.data as List<ProjectChangeRequest>?) ?? [];
    final pending = requests.where((r) => r.effectiveStatus == ApprovalStatus.pending);
    setState(() {
      _pendingChangeRequest = pending.isEmpty ? null : pending.first;
    });
  }

  @override
  void dispose() {
    _revisedHoursController.dispose();
    _revisedMinutesController.dispose();
    _revisedSecondsController.dispose();
    _remarksController.dispose();
    _buildingClassificationController.dispose();
    _structureClassificationController.dispose();
    _numberOfFloorsController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  /// Fires on every keystroke in any of the three Revised Working Hours
  /// boxes - re-runs validation (via [setState], so the combined error text
  /// stays current) and re-checks the timeline-overflow warning below.
  void _onRevisedWorkingHoursChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeShowTimelineWarning();
  }

  /// Non-blocking heads-up (see [ModuleValidator.estimatedMinutesWithinTimeline])
  /// shown the moment the Revised Working Hours value would extend beyond
  /// the module's current start/end timeline. Purely informational - it
  /// never prevents editing and never touches the end date itself; the
  /// existing hard block in [_submit] is what actually stops the save.
  Future<void> _maybeShowTimelineWarning() async {
    final module = _module;
    if (module == null || !mounted) return;

    final revisedMinutes = ModuleValidator.durationBoxesToMinutes(
      _revisedHoursController.text,
      _revisedMinutesController.text,
      _revisedSecondsController.text,
    );
    final overflowing = ModuleValidator.estimatedMinutesWithinTimeline(
          revisedMinutes,
          module.startDate,
          _endDate ?? module.endDate,
        ) !=
        null;

    if (!overflowing) {
      _timelineWarningShown = false;
      return;
    }
    if (_timelineWarningShown) return;
    _timelineWarningShown = true;

    if (!context.canPushRoute) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Timeline Warning'),
        content: const Text(
          "The revised working hours extend beyond the project's current end date. "
          "Please extend the project's end date accordingly.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadUsersForRole(UserRole role, {bool forceRefresh = false}) async {
    if (!forceRefresh && _usersByRole.containsKey(role)) return;

    setState(() {
      _loadingByRole[role] = true;
      _errorByRole[role] = null;
    });

    final result = await DependencyInjection.projectRepository.getUsersByRole(role);
    if (!mounted) return;

    setState(() {
      if (result.success) {
        _usersByRole[role] = (result.data as List<ProjectMemberOption>?) ?? [];
      } else {
        _errorByRole[role] = result.message;
      }
      _loadingByRole[role] = false;
    });
  }

  ProjectMemberOption? _findById(List<ProjectMemberOption> options, int? id) {
    if (id == null) return null;
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  /// Seeds the form fields from the server's current module state exactly
  /// once each - guarded so a role list finishing its (independent) load
  /// later doesn't clobber a selection the user already changed, and so
  /// re-fetches (e.g. after Save) don't reset an in-progress edit. Revised
  /// Working Hours starts pre-filled with the module's current estimate -
  /// it's edited in place to become the new total, not an amount to add.
  void _prefillFromModule(ModuleSummary module) {
    _module = module;
    if (!_scalarFieldsInitialized) {
      final minutes = module.estimatedMinutes ?? 0;
      _revisedHoursController.text = (minutes ~/ 60).toString();
      _revisedMinutesController.text = (minutes % 60).toString();
      _revisedSecondsController.text = '0';
      _endDate = module.endDate;
      _status = ProjectStatusX.fromApiValue(module.status);
      _buildingClassificationController.text = module.buildingClassification ?? '';
      _structureClassificationController.text = module.structureClassification ?? '';
      _numberOfFloorsController.text = module.numberOfFloors?.toString() ?? '';
      _areaController.text = module.area != null ? _formatArea(module.area!) : '';
      _scalarFieldsInitialized = true;
    }

    if (!_teamLeaderInitialized) {
      final options = _usersByRole[UserRole.teamLeader];
      if (options != null) {
        _teamLeader = _findById(options, module.teamLeadId);
        _teamLeaderInitialized = true;
      }
    }

    if (!_employeesInitialized) {
      final options = _usersByRole[UserRole.employee];
      if (options != null) {
        final memberIds = module.members.map((m) => m.userId).toSet();
        _selectedEmployees
          ..clear()
          ..addAll(options.where((u) => memberIds.contains(u.id)));
        _employeesInitialized = true;
      }
    }

    if (!_activitiesInitialized) {
      _selectedBillableActivities
        ..clear()
        ..addAll(module.billableActivities);
      _selectedNonBillableActivities
        ..clear()
        ..addAll(module.nonBillableActivities);
      _activitiesInitialized = true;
    }
  }

  Future<void> _pickTeamLeader() async {
    await _loadUsersForRole(UserRole.teamLeader);
    if (!mounted) return;
    final current = _teamLeader;
    await UserPickerSheet.show(
      context,
      title: 'Team Leader',
      users: _usersByRole[UserRole.teamLeader] ?? const [],
      isLoading: _loadingByRole[UserRole.teamLeader] ?? false,
      errorMessage: _errorByRole[UserRole.teamLeader],
      onRetry: () => _loadUsersForRole(UserRole.teamLeader, forceRefresh: true),
      multiSelect: false,
      initiallySelectedIds: current != null ? {current.id} : {},
      onSelect: (user) => setState(() => _teamLeader = user),
    );
  }

  Future<void> _pickEmployees() async {
    await _loadUsersForRole(UserRole.employee);
    if (!mounted) return;
    await UserPickerSheet.show(
      context,
      title: 'Employees',
      users: _usersByRole[UserRole.employee] ?? const [],
      isLoading: _loadingByRole[UserRole.employee] ?? false,
      errorMessage: _errorByRole[UserRole.employee],
      onRetry: () => _loadUsersForRole(UserRole.employee, forceRefresh: true),
      multiSelect: true,
      initiallySelectedIds: _selectedEmployees.map((e) => e.id).toSet(),
      onSelect: (user) {
        setState(() {
          if (_selectedEmployees.contains(user)) {
            _selectedEmployees.remove(user);
          } else {
            _selectedEmployees.add(user);
          }
        });
      },
    );
  }

  Future<void> _pickBillableActivities(ActivityViewModel activityViewModel) async {
    await MultiSelectPickerSheet.show<Activity>(
      context,
      title: 'Billable Activities',
      items: activityViewModel.activities,
      isLoading: activityViewModel.loadState == ActivityLoadState.loading,
      errorMessage: activityViewModel.loadState == ActivityLoadState.error
          ? activityViewModel.errorMessage
          : null,
      onRetry: () => activityViewModel.fetchActivities(),
      initiallySelectedIds:
          _selectedBillableActivities.map((a) => a.id).toSet(),
      itemId: (activity) => activity.id,
      itemLabel: (activity) => activity.name,
      onSelect: (activity) {
        setState(() {
          if (_selectedBillableActivities.contains(activity)) {
            _selectedBillableActivities.remove(activity);
          } else {
            _selectedBillableActivities.add(activity);
          }
        });
      },
    );
  }

  Future<void> _pickNonBillableActivities(ActivityViewModel activityViewModel) async {
    await MultiSelectPickerSheet.show<Activity>(
      context,
      title: 'Non-Billable Activities',
      items: activityViewModel.activities,
      isLoading: activityViewModel.loadState == ActivityLoadState.loading,
      errorMessage: activityViewModel.loadState == ActivityLoadState.error
          ? activityViewModel.errorMessage
          : null,
      onRetry: () => activityViewModel.fetchActivities(),
      initiallySelectedIds:
          _selectedNonBillableActivities.map((a) => a.id).toSet(),
      itemId: (activity) => activity.id,
      itemLabel: (activity) => activity.name,
      onSelect: (activity) {
        setState(() {
          if (_selectedNonBillableActivities.contains(activity)) {
            _selectedNonBillableActivities.remove(activity);
          } else {
            _selectedNonBillableActivities.add(activity);
          }
        });
      },
    );
  }

  /// Trims a trailing ".0" so a whole-number area shows as "1200" rather
  /// than "1200.0" when prefilling the text field from the server value.
  String _formatArea(double value) {
    return value == value.truncateToDouble()
        ? value.truncate().toString()
        : value.toString();
  }

  Future<void> _submit(ModuleSummary module) async {
    final isFormValid = _formKey.currentState?.validate() ?? false;
    final teamLeaderError = ModuleValidator.teamLeader(_teamLeader);
    final employeesError = ModuleValidator.employees(_selectedEmployees);
    final endDateError = ModuleValidator.endDate(_endDate, module.startDate);
    final buildingClassificationError = ModuleValidator.buildingClassification(
        _buildingClassificationController.text);
    final structureClassificationError = ModuleValidator.structureClassification(
        _structureClassificationController.text);
    final numberOfFloorsError =
        ModuleValidator.numberOfFloors(_numberOfFloorsController.text);
    final areaError = ModuleValidator.area(_areaController.text);
    final revisedMinutes = ModuleValidator.durationBoxesToMinutes(
      _revisedHoursController.text,
      _revisedMinutesController.text,
      _revisedSecondsController.text,
    );
    final revisedMinimumError = ModuleValidator.estimatedWorkingHoursMinimum(
        revisedMinutes, 'Revised Working Hours');
    final timelineHoursError = ModuleValidator.estimatedMinutesWithinTimeline(
      revisedMinutes,
      module.startDate,
      _endDate ?? module.endDate,
    );

    if (!isFormValid ||
        teamLeaderError != null ||
        employeesError != null ||
        endDateError != null ||
        buildingClassificationError != null ||
        structureClassificationError != null ||
        numberOfFloorsError != null ||
        areaError != null ||
        revisedMinimumError != null ||
        timelineHoursError != null) {
      setState(() {});
      final firstError = teamLeaderError ??
          employeesError ??
          endDateError ??
          buildingClassificationError ??
          structureClassificationError ??
          numberOfFloorsError ??
          areaError ??
          revisedMinimumError ??
          timelineHoursError;
      if (firstError != null) {
        SnackbarUtil.showError(context, firstError);
      }
      return;
    }

    setState(() => _isSaving = true);

    final remarks = _remarksController.text.trim().isEmpty
        ? null
        : _remarksController.text.trim();

    final request = UpdateModuleRequest(
      teamLeadId: _teamLeader?.id,
      memberIds: _selectedEmployees.map((e) => e.id).toList(),
      billableActivityIds:
          _selectedBillableActivities.map((a) => a.id).toList(),
      nonBillableActivityIds:
          _selectedNonBillableActivities.map((a) => a.id).toList(),
      status: _cancelModule ? ProjectStatus.cancelled.apiValue : null,
      remarks: remarks,
      buildingClassification: _buildingClassificationController.text.trim(),
      structureClassification: _structureClassificationController.text.trim(),
      numberOfFloors: int.parse(_numberOfFloorsController.text.trim()),
      area: double.parse(_areaController.text.trim()),
    );

    final result = await context
        .read<ModuleViewModel>()
        .updateModule(widget.moduleId, request);

    // End Date/Estimated Hours no longer apply directly (see
    // UpdateModuleRequest) - if either changed from the module's current
    // values, that's submitted as a separate Captain-approval request
    // instead, as long as one isn't already pending. The hours side is a
    // straight replacement: whatever's entered in Revised Working Hours
    // becomes the module's new estimate outright (it can move up or down),
    // not an amount added on top of the current one.
    bool changeRequestSubmitted = false;
    String? changeRequestError;
    if (_pendingChangeRequest == null) {
      final endDateChanged = _endDate != null && !_isSameDate(_endDate, module.endDate);
      final hoursChanged = revisedMinutes != null &&
          revisedMinutes != (module.estimatedMinutes ?? 0);

      if (endDateChanged || hoursChanged) {
        final changeResult = await _approvalRepository.submitChangeRequest(
          SubmitChangeRequest(
            moduleId: widget.moduleId,
            proposedEndDate: endDateChanged ? _endDate : null,
            proposedEstimatedMinutes: hoursChanged ? revisedMinutes : null,
            remarks: remarks,
          ),
        );
        changeRequestSubmitted = changeResult.success;
        if (!changeResult.success) {
          changeRequestError = changeResult.message;
        }
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      final String message;
      final bool isError;
      if (changeRequestSubmitted) {
        message = '${result.message}. ${AppStrings.submitChangeRequestSuccess}';
        isError = false;
      } else if (changeRequestError != null) {
        message = '${result.message}, but the change request failed: $changeRequestError';
        isError = true;
      } else {
        message = result.message;
        isError = false;
      }
      // Passed through the pop result rather than shown here - popping right
      // after queuing a snackbar clears it before it can ever render, since
      // SnackbarDismissingObserver (main.dart) wipes the messenger on every
      // route change by design. The caller shows it once back on a settled
      // screen instead, after this navigation has already happened.
      Navigator.pop(context, (message: message, isError: isError));
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  /// Combined inline error for the Revised Working Hours Hours/Minutes/
  /// Seconds boxes - each box's own format check first (matching Create
  /// Module's boxes exactly), then the combined-total minimum.
  String? get _revisedWorkingHoursError {
    final hoursError = ModuleValidator.durationField(_revisedHoursController.text, 'Hours');
    if (hoursError != null) return hoursError;
    final minutesError =
        ModuleValidator.minutesOrSeconds(_revisedMinutesController.text, 'Minutes');
    if (minutesError != null) return minutesError;
    final secondsError =
        ModuleValidator.minutesOrSeconds(_revisedSecondsController.text, 'Seconds');
    if (secondsError != null) return secondsError;

    final totalMinutes = ModuleValidator.durationBoxesToMinutes(
      _revisedHoursController.text,
      _revisedMinutesController.text,
      _revisedSecondsController.text,
    );
    return ModuleValidator.estimatedWorkingHoursMinimum(totalMinutes, 'Revised Working Hours');
  }

  bool _isSameDate(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// A reason is only mandatory when the edit actually proposes an End
  /// Date/Estimated Hours change - the only edits that get routed into the
  /// Captain-approval `ModuleChangeRequest` flow. Every other edit (status,
  /// team, activities) needs no reason at all.
  bool _changeRequiresReason(ModuleSummary module) {
    final revisedMinutes = ModuleValidator.durationBoxesToMinutes(
      _revisedHoursController.text,
      _revisedMinutesController.text,
      _revisedSecondsController.text,
    );
    final endDateChanged = _endDate != null && !_isSameDate(_endDate, module.endDate);
    final hoursChanged = revisedMinutes != null &&
        revisedMinutes != (module.estimatedMinutes ?? 0);
    return endDateChanged || hoursChanged;
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ModuleViewModel>();
    final activityViewModel = context.watch<ActivityViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.editModuleTitle),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(context, viewModel, activityViewModel)),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ModuleViewModel viewModel,
    ActivityViewModel activityViewModel,
  ) {
    switch (viewModel.detailState) {
      case ModuleLoadState.initial:
      case ModuleLoadState.loading:
        return const AppLoader(message: 'Loading module...');

      case ModuleLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: 'Unable to load module',
          message: viewModel.detailErrorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchModuleDetails(widget.moduleId),
        );

      case ModuleLoadState.success:
        final module = viewModel.selectedModule;
        if (module == null) {
          return const AppEmptyView(
            icon: Icons.folder_off_outlined,
            title: 'Module not found',
          );
        }
        _prefillFromModule(module);
        return _buildForm(context, module, activityViewModel);
    }
  }

  Widget _buildForm(
    BuildContext context,
    ModuleSummary module,
    ActivityViewModel activityViewModel,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Module'),
            const SizedBox(height: AppDimensions.cardSpacing),
            _ReadOnlyField(
              label: 'Project',
              icon: Icons.folder_outlined,
              value: module.projectName,
            ),
            const SizedBox(height: AppDimensions.cardSpacing),
            _ReadOnlyField(
              label: 'Module Name',
              icon: Icons.widgets_outlined,
              value: module.moduleName,
            ),
            const SizedBox(height: AppDimensions.sectionSpacing),
            const SectionHeader('Building Details'),
            const SizedBox(height: AppDimensions.cardSpacing),
            AppTextField(
              controller: _buildingClassificationController,
              label: AppStrings.createProjectFieldBuildingClassification,
              icon: Icons.apartment_outlined,
              hintText: AppStrings.createProjectBuildingClassificationHint,
              validator: ModuleValidator.buildingClassification,
            ),
            const SizedBox(height: AppDimensions.cardSpacing),
            AppTextField(
              controller: _structureClassificationController,
              label: AppStrings.createProjectFieldStructureClassification,
              icon: Icons.foundation_outlined,
              hintText: AppStrings.createProjectStructureClassificationHint,
              validator: ModuleValidator.structureClassification,
            ),
            const SizedBox(height: AppDimensions.cardSpacing),
            AppTextField(
              controller: _numberOfFloorsController,
              label: AppStrings.createProjectFieldNumberOfFloors,
              icon: Icons.layers_outlined,
              keyboardType: TextInputType.number,
              validator: ModuleValidator.numberOfFloors,
            ),
            const SizedBox(height: AppDimensions.cardSpacing),
            AppTextField(
              controller: _areaController,
              label: AppStrings.createProjectFieldArea,
              icon: Icons.square_foot_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: ModuleValidator.area,
            ),
            const SizedBox(height: AppDimensions.sectionSpacing),
            const SectionHeader('Team'),
            const SizedBox(height: AppDimensions.cardSpacing),
            SingleUserPickerField(
              label: 'Team Leader',
              hintText: 'Select Team Leader',
              value: _teamLeader,
              errorText: ModuleValidator.teamLeader(_teamLeader),
              onTap: _pickTeamLeader,
            ),
            const SizedBox(height: AppDimensions.cardSpacing),
            EmployeesPickerField(
              selected: _selectedEmployees,
              errorText: ModuleValidator.employees(_selectedEmployees),
              enabled: true,
              onAdd: _pickEmployees,
              onRemove: (user) => setState(() => _selectedEmployees.remove(user)),
            ),
            const SizedBox(height: AppDimensions.sectionSpacing),
            const SectionHeader('Activities'),
            const SizedBox(height: AppDimensions.cardSpacing),
            MultiSelectChipField<Activity>(
              label: 'Billable Activities',
              addButtonLabel: 'Add',
              emptyText: 'No activities configured for this module yet.',
              selected: _selectedBillableActivities,
              itemLabel: (activity) => activity.name,
              errorText: null,
              onAdd: () => _pickBillableActivities(activityViewModel),
              onRemove: (activity) =>
                  setState(() => _selectedBillableActivities.remove(activity)),
            ),
            const SizedBox(height: AppDimensions.cardSpacing),
            MultiSelectChipField<Activity>(
              label: 'Non-Billable Activities',
              addButtonLabel: 'Add',
              emptyText: 'No activities configured for this module yet.',
              selected: _selectedNonBillableActivities,
              itemLabel: (activity) => activity.name,
              errorText: null,
              onAdd: () => _pickNonBillableActivities(activityViewModel),
              onRemove: (activity) => setState(
                  () => _selectedNonBillableActivities.remove(activity)),
            ),
            const SizedBox(height: AppDimensions.sectionSpacing),
            const SectionHeader('Revision'),
            const SizedBox(height: AppDimensions.cardSpacing),
            if (_pendingChangeRequest != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(AppStrings.submitChangeRequestPendingBanner),
              ),
              const SizedBox(height: AppDimensions.cardSpacing),
            ],
            IgnorePointer(
              ignoring: _pendingChangeRequest != null,
              child: Opacity(
                opacity: _pendingChangeRequest != null ? 0.6 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppDatePicker(
                      label: 'New End Date',
                      value: _endDate,
                      firstDate: module.startDate,
                      onChanged: (date) => setState(() => _endDate = date),
                      validator: (_) =>
                          ModuleValidator.endDate(_endDate, module.startDate),
                    ),
                    const SizedBox(height: AppDimensions.cardSpacing),
                    EstimatedDurationInput(
                      label: 'Revised Working Hours',
                      hoursController: _revisedHoursController,
                      minutesController: _revisedMinutesController,
                      secondsController: _revisedSecondsController,
                      errorText: _revisedWorkingHoursError,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.cardSpacing),
            _ReadOnlyField(
              label: 'Status',
              icon: Icons.flag_outlined,
              value: _status.label,
            ),
            if (_status != ProjectStatus.cancelled) ...[
              const SizedBox(height: AppDimensions.cardSpacing),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Cancel this module'),
                subtitle: const Text(
                  'Cancelling is permanent - the module becomes view-only and can no '
                  'longer be edited, progressed or billed.',
                ),
                value: _cancelModule,
                onChanged: (checked) =>
                    setState(() => _cancelModule = checked ?? false),
              ),
            ],
            if (_changeRequiresReason(module)) ...[
              const SizedBox(height: AppDimensions.cardSpacing),
              AppTextField(
                controller: _remarksController,
                label: 'Reason for change',
                icon: Icons.notes_outlined,
                maxLines: 3,
                validator: ModuleValidator.reasonForChange,
              ),
            ],
            const SizedBox(height: AppDimensions.sectionSpacing),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Cancel',
                    outlined: true,
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: AppDimensions.cardSpacing),
                Expanded(
                  child: AppButton(
                    text: 'Save',
                    isLoading: _isSaving,
                    onPressed: _isSaving ? null : () => _submit(module),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Static, non-editable field matching [AppTextField]'s visual style -
/// used for context (Project / Module Name) that this screen shows but
/// never lets the user change.
class _ReadOnlyField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;

  const _ReadOnlyField({
    required this.label,
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      child: Text(value),
    );
  }
}
