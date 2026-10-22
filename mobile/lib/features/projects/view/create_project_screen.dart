import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_date_picker.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/multi_select_chip_field.dart';
import '../../../shared/widgets/multi_select_picker_sheet.dart';
import '../../activities/model/activity.dart';
import '../../activities/viewmodel/activity_view_model.dart';
import '../../modules/utils/module_validator.dart';
import '../model/project_list_item.dart';
import '../utils/project_validator.dart';
import '../viewmodel/create_project_view_model.dart';
import '../widgets/estimated_duration_input.dart';
import '../widgets/section_header.dart';
import '../widgets/team_assignment_fields.dart';
import '../widgets/user_picker_sheet.dart';
import 'review_project_screen.dart';

/// Entry point for the Create Project/Module wizard (Captain / Project
/// Controller only - enforced both by the backend's `@PreAuthorize` on
/// `POST /api/projects` / `POST /api/modules` and by [ProjectListScreen]
/// only showing the entry point to those roles). Hosts the shared
/// [CreateProjectViewModel] so the Review screen (pushed on top) sees the
/// same in-progress state, and so "Edit" from Review simply pops back here
/// with everything intact.
///
/// A project is never created alone - it always comes with its first
/// module. [preselectedProjectId] lets [ProjectDetailsScreen]'s "Add
/// Module" action open this same flow pre-scoped to Existing Project with
/// that project already chosen.
///
/// Team assignment is a strict hierarchy: Team Leader -> Employees. See
/// [CreateProjectViewModel]'s doc comment for why the Employees picker
/// isn't actually filtered by the Team Leader selection yet (no backend
/// relationship exists).
class CreateProjectScreen extends StatelessWidget {
  final int? preselectedProjectId;

  const CreateProjectScreen({super.key, this.preselectedProjectId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CreateProjectViewModel>(
      create: (_) => CreateProjectViewModel(
        projectRepository: DependencyInjection.projectRepository,
        moduleRepository: DependencyInjection.moduleRepository,
      ),
      child: _CreateProjectView(preselectedProjectId: preselectedProjectId),
    );
  }
}

class _CreateProjectView extends StatefulWidget {
  final int? preselectedProjectId;

  const _CreateProjectView({this.preselectedProjectId});

  @override
  State<_CreateProjectView> createState() => _CreateProjectViewState();
}

class _CreateProjectViewState extends State<_CreateProjectView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _clientIdController;
  late final TextEditingController _projectNameController;
  late final TextEditingController _projectCodeController;
  late final TextEditingController _moduleNameController;
  late final TextEditingController _buildingClassificationController;
  late final TextEditingController _structureClassificationController;
  late final TextEditingController _numberOfFloorsController;
  late final TextEditingController _areaController;
  late final TextEditingController _hoursController;
  late final TextEditingController _minutesController;
  late final TextEditingController _secondsController;

  @override
  void initState() {
    super.initState();
    final viewModel = context.read<CreateProjectViewModel>();
    _clientIdController = TextEditingController(text: viewModel.clientId);
    _projectNameController = TextEditingController(text: viewModel.projectName);
    _projectCodeController = TextEditingController(text: viewModel.projectCode);
    _moduleNameController = TextEditingController(text: viewModel.moduleName);
    _buildingClassificationController =
        TextEditingController(text: viewModel.buildingClassification);
    _structureClassificationController =
        TextEditingController(text: viewModel.structureClassification);
    _numberOfFloorsController =
        TextEditingController(text: viewModel.numberOfFloorsText);
    _areaController = TextEditingController(text: viewModel.areaText);
    _hoursController = TextEditingController(text: viewModel.hoursText);
    _minutesController = TextEditingController(text: viewModel.minutesText);
    _secondsController = TextEditingController(text: viewModel.secondsText);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final activityViewModel = context.read<ActivityViewModel>();
      if (activityViewModel.loadState == ActivityLoadState.initial) {
        activityViewModel.fetchActivities();
      }
      if (widget.preselectedProjectId != null) {
        viewModel.setIsNewProject(false);
        await viewModel.loadExistingProjects();
        if (!mounted) return;
        final preselected = viewModel.existingProjects
            .where((p) => p.id == widget.preselectedProjectId)
            .toList();
        if (preselected.isNotEmpty) {
          viewModel.setExistingProject(preselected.first);
        }
      }
    });
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _projectNameController.dispose();
    _projectCodeController.dispose();
    _moduleNameController.dispose();
    _buildingClassificationController.dispose();
    _structureClassificationController.dispose();
    _numberOfFloorsController.dispose();
    _areaController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  Future<void> _pickTeamLeader(CreateProjectViewModel viewModel) async {
    await viewModel.loadUsersForRole(UserRole.teamLeader);
    if (!mounted) return;
    final current = viewModel.teamLeader;
    await UserPickerSheet.show(
      context,
      title: AppStrings.createProjectFieldTeamLeader,
      users: viewModel.usersFor(UserRole.teamLeader),
      isLoading: viewModel.isLoadingUsersFor(UserRole.teamLeader),
      errorMessage: viewModel.usersErrorFor(UserRole.teamLeader),
      onRetry: () =>
          viewModel.loadUsersForRole(UserRole.teamLeader, forceRefresh: true),
      multiSelect: false,
      initiallySelectedIds: current != null ? {current.id} : {},
      onSelect: viewModel.setTeamLeader,
    );
  }

  Future<void> _pickEmployees(CreateProjectViewModel viewModel) async {
    await viewModel.loadUsersForRole(UserRole.employee);
    if (!mounted) return;
    await UserPickerSheet.show(
      context,
      title: AppStrings.createProjectFieldEmployees,
      users: viewModel.usersFor(UserRole.employee),
      isLoading: viewModel.isLoadingUsersFor(UserRole.employee),
      errorMessage: viewModel.usersErrorFor(UserRole.employee),
      onRetry: () =>
          viewModel.loadUsersForRole(UserRole.employee, forceRefresh: true),
      multiSelect: true,
      initiallySelectedIds:
          viewModel.selectedEmployees.map((employee) => employee.id).toSet(),
      onSelect: viewModel.toggleEmployee,
    );
  }

  Future<void> _pickBillableActivities(
    CreateProjectViewModel viewModel,
    ActivityViewModel activityViewModel,
  ) async {
    await MultiSelectPickerSheet.show<Activity>(
      context,
      title: AppStrings.billableActivitiesLabel,
      items: activityViewModel.activities,
      isLoading: activityViewModel.loadState == ActivityLoadState.loading,
      errorMessage: activityViewModel.loadState == ActivityLoadState.error
          ? activityViewModel.errorMessage
          : null,
      onRetry: () => activityViewModel.fetchActivities(),
      initiallySelectedIds:
          viewModel.selectedBillableActivities.map((a) => a.id).toSet(),
      itemId: (activity) => activity.id,
      itemLabel: (activity) => activity.name,
      onSelect: viewModel.toggleBillableActivity,
    );
  }

  Future<void> _pickNonBillableActivities(
    CreateProjectViewModel viewModel,
    ActivityViewModel activityViewModel,
  ) async {
    await MultiSelectPickerSheet.show<Activity>(
      context,
      title: AppStrings.nonBillableActivitiesLabel,
      items: activityViewModel.activities,
      isLoading: activityViewModel.loadState == ActivityLoadState.loading,
      errorMessage: activityViewModel.loadState == ActivityLoadState.error
          ? activityViewModel.errorMessage
          : null,
      onRetry: () => activityViewModel.fetchActivities(),
      initiallySelectedIds:
          viewModel.selectedNonBillableActivities.map((a) => a.id).toSet(),
      itemId: (activity) => activity.id,
      itemLabel: (activity) => activity.name,
      onSelect: viewModel.toggleNonBillableActivity,
    );
  }

  void _continue(CreateProjectViewModel viewModel) {
    final isFormValid = _formKey.currentState?.validate() ?? false;

    viewModel.setProjectName(_projectNameController.text);
    viewModel.setProjectCode(_projectCodeController.text);
    viewModel.setClientId(_clientIdController.text);
    viewModel.setModuleName(_moduleNameController.text);
    viewModel.setBuildingClassification(_buildingClassificationController.text);
    viewModel.setStructureClassification(_structureClassificationController.text);
    viewModel.setNumberOfFloorsText(_numberOfFloorsController.text);
    viewModel.setAreaText(_areaController.text);
    viewModel.setHoursText(_hoursController.text);
    viewModel.setMinutesText(_minutesController.text);
    viewModel.setSecondsText(_secondsController.text);

    final isViewModelValid = viewModel.validate();

    if (!isFormValid || !isViewModelValid) {
      final firstError = viewModel.fieldErrors.values.isNotEmpty
          ? viewModel.fieldErrors.values.first
          : null;
      if (firstError != null) {
        SnackbarUtil.showError(context, firstError);
      }
      return;
    }

    if (!context.canPushRoute) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        // Navigator.push inserts the new route into the app's root Overlay,
        // outside this screen's local ChangeNotifierProvider subtree - the
        // same instance must be re-provided explicitly so Review sees the
        // values just entered here.
        builder: (_) => ChangeNotifierProvider.value(
          value: viewModel,
          child: const ReviewProjectScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CreateProjectViewModel>();
    final activityViewModel = context.watch<ActivityViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.createProjectTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProjectChoice(viewModel),
                const SizedBox(height: AppDimensions.sectionSpacing),
                if (viewModel.isNewProject)
                  _buildNewProjectFields()
                else
                  _buildExistingProjectField(viewModel),
                const SizedBox(height: AppDimensions.sectionSpacing),
                const SectionHeader(AppStrings.createProjectSectionModule),
                const SizedBox(height: AppDimensions.cardSpacing),
                AppTextField(
                  controller: _moduleNameController,
                  label: AppStrings.createProjectFieldModuleName,
                  icon: Icons.widgets_outlined,
                  hintText: AppStrings.createProjectModuleNameHint,
                  validator: ModuleValidator.moduleName,
                ),
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
                const SectionHeader(AppStrings.createProjectSectionTeam),
                const SizedBox(height: AppDimensions.cardSpacing),
                SingleUserPickerField(
                  label: AppStrings.createProjectFieldTeamLeader,
                  hintText: AppStrings.createProjectSelectTeamLeaderHint,
                  value: viewModel.teamLeader,
                  errorText: viewModel.fieldErrors['teamLeader'],
                  onTap: () => _pickTeamLeader(viewModel),
                ),
                const SizedBox(height: AppDimensions.cardSpacing),
                EmployeesPickerField(
                  selected: viewModel.selectedEmployees,
                  errorText: viewModel.fieldErrors['employees'],
                  enabled: viewModel.teamLeader != null,
                  disabledHintText: AppStrings.createProjectSelectParentFirst(
                    AppStrings.createProjectFieldTeamLeader,
                  ),
                  onAdd: () => _pickEmployees(viewModel),
                  onRemove: viewModel.toggleEmployee,
                ),
                const SizedBox(height: AppDimensions.sectionSpacing),
                const SectionHeader(AppStrings.dashboardModuleActivities),
                const SizedBox(height: AppDimensions.cardSpacing),
                MultiSelectChipField<Activity>(
                  label: AppStrings.billableActivitiesLabel,
                  addButtonLabel: AppStrings.activityListAddButton,
                  emptyText: AppStrings.activitiesEmptyForProjectMessage,
                  selected: viewModel.selectedBillableActivities,
                  itemLabel: (activity) => activity.name,
                  errorText: viewModel.fieldErrors['billableActivities'],
                  onAdd: () => _pickBillableActivities(viewModel, activityViewModel),
                  onRemove: viewModel.toggleBillableActivity,
                ),
                const SizedBox(height: AppDimensions.cardSpacing),
                MultiSelectChipField<Activity>(
                  label: AppStrings.nonBillableActivitiesLabel,
                  addButtonLabel: AppStrings.activityListAddButton,
                  emptyText: AppStrings.activitiesEmptyForProjectMessage,
                  selected: viewModel.selectedNonBillableActivities,
                  itemLabel: (activity) => activity.name,
                  errorText: viewModel.fieldErrors['nonBillableActivities'],
                  onAdd: () =>
                      _pickNonBillableActivities(viewModel, activityViewModel),
                  onRemove: viewModel.toggleNonBillableActivity,
                ),
                const SizedBox(height: AppDimensions.sectionSpacing),
                const SectionHeader(AppStrings.createProjectSectionTimeline),
                const SizedBox(height: AppDimensions.cardSpacing),
                AppDatePicker(
                  label: AppStrings.createProjectFieldStartDate,
                  value: viewModel.startDate,
                  firstDate: DateTime.now(),
                  onChanged: viewModel.setStartDate,
                  validator: (_) =>
                      ModuleValidator.startDate(viewModel.startDate),
                ),
                const SizedBox(height: AppDimensions.cardSpacing),
                AppDatePicker(
                  label: AppStrings.createProjectFieldEndDate,
                  value: viewModel.endDate,
                  firstDate: viewModel.startDate,
                  onChanged: viewModel.setEndDate,
                  validator: (_) => ModuleValidator.endDate(
                    viewModel.endDate,
                    viewModel.startDate,
                  ),
                ),
                const SizedBox(height: AppDimensions.cardSpacing),
                EstimatedDurationInput(
                  label: AppStrings.createProjectFieldEstimatedHours,
                  hoursController: _hoursController,
                  minutesController: _minutesController,
                  secondsController: _secondsController,
                  errorText: viewModel.fieldErrors['hours'] ??
                      viewModel.fieldErrors['minutes'] ??
                      viewModel.fieldErrors['seconds'],
                ),
                const SizedBox(height: AppDimensions.sectionSpacing),
                AppButton(
                  text: AppStrings.createProjectReviewButton,
                  onPressed: () => _continue(viewModel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProjectChoice(CreateProjectViewModel viewModel) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text(AppStrings.createProjectChoiceNewProject)),
        ButtonSegment(value: false, label: Text(AppStrings.createProjectChoiceExistingProject)),
      ],
      selected: {viewModel.isNewProject},
      onSelectionChanged: (selection) {
        final isNew = selection.first;
        viewModel.setIsNewProject(isNew);
        if (!isNew) {
          viewModel.loadExistingProjects();
        }
      },
    );
  }

  Widget _buildNewProjectFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(AppStrings.createProjectSectionInformation),
        const SizedBox(height: AppDimensions.cardSpacing),
        AppTextField(
          controller: _projectNameController,
          label: AppStrings.createProjectFieldProjectName,
          icon: Icons.folder_outlined,
          validator: ProjectValidator.projectName,
        ),
        const SizedBox(height: AppDimensions.cardSpacing),
        AppTextField(
          controller: _projectCodeController,
          label: AppStrings.createProjectFieldProjectId,
          icon: Icons.tag,
          validator: ProjectValidator.projectCode,
        ),
        const SizedBox(height: AppDimensions.cardSpacing),
        AppTextField(
          controller: _clientIdController,
          label: AppStrings.createProjectFieldClientId,
          icon: Icons.badge_outlined,
        ),
      ],
    );
  }

  Widget _buildExistingProjectField(CreateProjectViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(AppStrings.createProjectSectionInformation),
        const SizedBox(height: AppDimensions.cardSpacing),
        if (viewModel.projectsError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              viewModel.projectsError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        AppDropdown<ProjectListItem>(
          label: AppStrings.createProjectFieldExistingProject,
          icon: Icons.folder_outlined,
          value: viewModel.existingProject,
          items: viewModel.existingProjects,
          itemLabel: (p) => '${p.projectName} (${p.projectCode})',
          onChanged: viewModel.setExistingProject,
          validator: (_) => viewModel.fieldErrors['existingProject'],
        ),
      ],
    );
  }
}
