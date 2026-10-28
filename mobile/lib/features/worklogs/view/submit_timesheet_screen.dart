import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_date_picker.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/multi_select_chip_field.dart';
import '../../../shared/widgets/multi_select_picker_sheet.dart';
import '../../activities/model/activity.dart';
import '../../modules/model/module_list_item.dart';
import '../../modules/viewmodel/module_view_model.dart';
import '../../projects/model/project_list_item.dart';
import '../../projects/viewmodel/project_view_model.dart';
import '../../projects/widgets/estimated_duration_input.dart';
import '../model/create_work_log_request.dart';
import '../utils/timesheet_validator.dart';
import '../viewmodel/work_log_view_model.dart';

/// Log Hours form (Employee only). Project options come from
/// [ProjectViewModel.fetchWorkLogProjects] - `GET
/// /projects?hasInProgressModule=true` is scoped on the backend to "projects
/// this user is assigned to (via a module) with at least one of their own
/// modules In Progress" (see `ProjectServiceImpl#getProjects`), so a project
/// where every module of theirs has gone Inactive/Completed never shows up
/// here in the first place. Picking a project then loads that project's
/// modules from [ModuleViewModel] - `GET /modules?projectId=` is scoped the
/// same way at the module level, so this screen can't offer a module the
/// submit call would reject (see `WorkLogServiceImpl#submitWorkLog`).
class SubmitTimesheetScreen extends StatefulWidget {
  const SubmitTimesheetScreen({super.key});

  @override
  State<SubmitTimesheetScreen> createState() => _SubmitTimesheetScreenState();
}

class _SubmitTimesheetScreenState extends State<SubmitTimesheetScreen> {
  final _formKey = GlobalKey<FormState>();
  // Billable/Non-Billable Hours Worked are each collected as three separate
  // Hours/Minutes/Seconds boxes (see EstimatedDurationInput), one set per
  // category, positioned directly under that category's Activities picker -
  // all default to "0" and are converted to seconds for
  // CreateWorkLogRequest (see _computeBillableDurationSeconds/
  // _computeNonBillableDurationSeconds).
  final _billableHoursController = TextEditingController(text: '0');
  final _billableMinutesController = TextEditingController(text: '0');
  final _billableSecondsController = TextEditingController(text: '0');
  final _nonBillableHoursController = TextEditingController(text: '0');
  final _nonBillableMinutesController = TextEditingController(text: '0');
  final _nonBillableSecondsController = TextEditingController(text: '0');
  final _workDoneController = TextEditingController();

  ProjectListItem? _project;
  ModuleListItem? _module;
  DateTime? _workDate;
  String? _billableHoursError;
  String? _nonBillableHoursError;
  final List<Activity> _selectedBillableActivities = [];
  final List<Activity> _selectedNonBillableActivities = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Always fetch (not just when uninitialized): this ViewModel is shared
      // app-wide, but [fetchWorkLogProjects] writes to its own cache
      // ([ProjectViewModel.workLogProjects]), separate from the general
      // Project List screen's, so refetching here can't clobber that
      // screen's already-loaded (differently-scoped) list.
      context.read<ProjectViewModel>().fetchWorkLogProjects();
    });
  }

  @override
  void dispose() {
    _billableHoursController.dispose();
    _billableMinutesController.dispose();
    _billableSecondsController.dispose();
    _nonBillableHoursController.dispose();
    _nonBillableMinutesController.dispose();
    _nonBillableSecondsController.dispose();
    _workDoneController.dispose();
    super.dispose();
  }

  /// Hours/Minutes/Seconds -> the exact total-seconds value
  /// TimesheetValidator.durationSeconds/CreateWorkLogRequest expect. Blank or
  /// non-numeric boxes fall back to 0, so a partially-filled input (e.g.
  /// only Hours) is treated as the rest being 0, exactly as specified.
  /// Pure integer arithmetic - nothing here is rounded or approximated.
  int _computeSeconds(TextEditingController hours, TextEditingController minutes,
      TextEditingController seconds) {
    final h = int.tryParse(hours.text.trim()) ?? 0;
    final m = int.tryParse(minutes.text.trim()) ?? 0;
    final s = int.tryParse(seconds.text.trim()) ?? 0;
    return h * 3600 + m * 60 + s;
  }

  int _computeBillableDurationSeconds() => _computeSeconds(
      _billableHoursController, _billableMinutesController, _billableSecondsController);

  int _computeNonBillableDurationSeconds() => _computeSeconds(
      _nonBillableHoursController, _nonBillableMinutesController, _nonBillableSecondsController);

  void _onProjectChanged(ProjectListItem? project) {
    setState(() {
      _project = project;
      _module = null;
      _workDate = null;
      _selectedBillableActivities.clear();
      _selectedNonBillableActivities.clear();
    });
    if (project != null) {
      context.read<ModuleViewModel>().fetchModules(projectId: project.id);
    }
  }

  /// Re-fetches full module details on selection so the Billable/Non-
  /// Billable Activities pickers can be scoped to just this module's
  /// configured activities (see `ModuleViewModel.selectedModule`) - clears
  /// any previously-picked activities, since they belonged to the prior
  /// module's configuration and may not even exist on this one.
  void _onModuleChanged(ModuleListItem? module) {
    setState(() {
      _module = module;
      // The date range (firstDate/lastDate) is scoped to the module, so a
      // date picked under the previous module may fall outside this one's
      // window - clear it rather than silently carrying over a stale value.
      _workDate = null;
      _selectedBillableActivities.clear();
      _selectedNonBillableActivities.clear();
    });
    if (module != null) {
      context.read<ModuleViewModel>().fetchModuleDetails(module.id);
    }
  }

  Future<void> _pickBillableActivities(List<Activity> moduleActivities) async {
    await MultiSelectPickerSheet.show<Activity>(
      context,
      title: AppStrings.billableActivitiesLabel,
      items: moduleActivities,
      isLoading: false,
      errorMessage: null,
      onRetry: null,
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

  Future<void> _pickNonBillableActivities(List<Activity> moduleActivities) async {
    await MultiSelectPickerSheet.show<Activity>(
      context,
      title: AppStrings.nonBillableActivitiesLabel,
      items: moduleActivities,
      isLoading: false,
      errorMessage: null,
      onRetry: null,
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

  Future<void> _submit() async {
    if (context.read<WorkLogViewModel>().isSubmitting) return;

    final isFormValid = _formKey.currentState?.validate() ?? false;
    final projectError = TimesheetValidator.project(_project);
    final moduleError = TimesheetValidator.module(_module);
    final dateError = TimesheetValidator.workDate(
      _workDate,
      startDate: _module?.startDate,
      endDate: _module?.endDate,
    );
    final activityError = TimesheetValidator.activitySelection(
      _selectedBillableActivities,
      _selectedNonBillableActivities,
    );

    final hasBillableActivities = _selectedBillableActivities.isNotEmpty;
    final hasNonBillableActivities = _selectedNonBillableActivities.isNotEmpty;
    final billableSeconds = _computeBillableDurationSeconds();
    final nonBillableSeconds = _computeNonBillableDurationSeconds();

    final billableBoxError =
        TimesheetValidator.validateMinutes(_billableMinutesController.text) ??
            TimesheetValidator.validateSeconds(_billableSecondsController.text) ??
            TimesheetValidator.categoryHoursWorked(
              hasActivities: hasBillableActivities,
              seconds: billableSeconds,
              hoursFieldLabel: AppStrings.billableHoursWorkedLabel,
              activityFieldLabel: 'Billable Activity',
            );
    final nonBillableBoxError = TimesheetValidator.validateMinutes(
            _nonBillableMinutesController.text) ??
        TimesheetValidator.validateSeconds(_nonBillableSecondsController.text) ??
        TimesheetValidator.categoryHoursWorked(
          hasActivities: hasNonBillableActivities,
          seconds: nonBillableSeconds,
          hoursFieldLabel: AppStrings.nonBillableHoursWorkedLabel,
          activityFieldLabel: 'Non-Billable Activity',
        );
    final combinedError = (billableBoxError == null && nonBillableBoxError == null)
        ? TimesheetValidator.combinedDurationSeconds(billableSeconds, nonBillableSeconds)
        : null;

    final timeError = billableBoxError ?? nonBillableBoxError ?? combinedError;

    if (!isFormValid ||
        projectError != null ||
        moduleError != null ||
        dateError != null ||
        activityError != null ||
        timeError != null) {
      setState(() {
        _billableHoursError = billableBoxError;
        _nonBillableHoursError = nonBillableBoxError;
      });
      final firstError =
          projectError ?? moduleError ?? dateError ?? activityError ?? timeError;
      if (firstError != null) {
        SnackbarUtil.showError(context, firstError);
      }
      return;
    }

    setState(() {
      _billableHoursError = null;
      _nonBillableHoursError = null;
    });

    final request = CreateWorkLogRequest(
      moduleId: _module!.id,
      workDate: _workDate!,
      billableDurationSeconds: hasBillableActivities ? billableSeconds : null,
      nonBillableDurationSeconds: hasNonBillableActivities ? nonBillableSeconds : null,
      workDone: _workDoneController.text.trim(),
      billableActivityIds:
          _selectedBillableActivities.map((a) => a.id).toList(),
      nonBillableActivityIds:
          _selectedNonBillableActivities.map((a) => a.id).toList(),
    );

    final result = await context.read<WorkLogViewModel>().submitWorkLog(request);
    if (!mounted) return;

    if (result.success) {
      // Passed through the pop result rather than shown here - popping right
      // after queuing a snackbar clears it before it can render, since
      // SnackbarDismissingObserver wipes the messenger on every route
      // change. The caller (TimesheetListScreen._openSubmit) shows it once
      // back on a settled screen instead.
      Navigator.pop(context, AppStrings.timesheetSubmitSuccess);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectViewModel = context.watch<ProjectViewModel>();
    final moduleViewModel = context.watch<ModuleViewModel>();
    final workLogViewModel = context.watch<WorkLogViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.submitTimesheetTitle),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(projectViewModel, moduleViewModel, workLogViewModel)),
    );
  }

  Widget _buildBody(
    ProjectViewModel projectViewModel,
    ModuleViewModel moduleViewModel,
    WorkLogViewModel workLogViewModel,
  ) {
    if (TimesheetValidator.isLoggingClosedToday()) {
      return const AppEmptyView(
        icon: Icons.event_busy_outlined,
        title: 'Work logs are closed on Sunday',
        message:
            'The past week locks when Sunday starts. Logging reopens on Monday.',
      );
    }

    if (projectViewModel.workLogLoadState == ProjectLoadState.initial ||
        projectViewModel.workLogLoadState == ProjectLoadState.loading) {
      return const AppLoader(message: 'Loading your projects...');
    }

    if (projectViewModel.workLogLoadState == ProjectLoadState.error) {
      return AppEmptyView(
        icon: Icons.cloud_off_outlined,
        title: 'Unable to load projects',
        message: projectViewModel.workLogErrorMessage,
        actionLabel: 'Retry',
        onAction: () => projectViewModel.fetchWorkLogProjects(),
      );
    }

    // The backend already scoped this list to "has an In Progress module of
    // mine" (see the class doc comment) - `isActive` is still checked here
    // as defense in depth, since a project can be deactivated independently
    // of an individual module's own status.
    final projects = projectViewModel.workLogProjects.where((p) => p.isActive).toList();
    if (projects.isEmpty) {
      return const AppEmptyView(
        icon: Icons.folder_off_outlined,
        title: 'No projects assigned',
        message: AppStrings.timesheetNoProjectsMessage,
      );
    }

    final modulesReady = _project != null &&
        moduleViewModel.loadState == ModuleLoadState.success;
    final eligibleModules = modulesReady
        ? moduleViewModel.modules
            .where((m) =>
                m.status == 'IN_PROGRESS' &&
                m.billingStatus != 'FULL_PAYMENT_RECEIVED' &&
                !TimesheetValidator.isModuleExpiredForLogging(m.endDate))
            .toList()
        : const <ModuleListItem>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppDropdown<ProjectListItem>(
              label: AppStrings.timesheetFieldProject,
              icon: Icons.folder_outlined,
              value: _project,
              items: projects,
              itemLabel: (p) => p.projectName,
              onChanged: _onProjectChanged,
            ),
            if (_project != null) ...[
              const SizedBox(height: AppDimensions.cardSpacing),
              if (_project != null && moduleViewModel.loadState == ModuleLoadState.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else
                AppDropdown<ModuleListItem>(
                  label: 'Module',
                  icon: Icons.widgets_outlined,
                  value: _module,
                  items: eligibleModules,
                  itemLabel: (m) => m.moduleName,
                  onChanged: _onModuleChanged,
                  emptyHint: 'No modules in progress for this project',
                ),
            ],
            if (_module != null) ...[
              const SizedBox(height: AppDimensions.cardSpacing),
              Builder(builder: (context) {
                final detail = moduleViewModel.selectedModule;
                final detailReady = detail != null && detail.id == _module!.id;
                final billableActivities =
                    detailReady ? detail.billableActivities : const <Activity>[];
                final nonBillableActivities = detailReady
                    ? detail.nonBillableActivities
                    : const <Activity>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MultiSelectChipField<Activity>(
                      label: AppStrings.billableActivitiesLabel,
                      addButtonLabel: AppStrings.activityListAddButton,
                      emptyText: AppStrings.activitiesEmptyForProjectMessage,
                      disabledHintText: 'Loading activities...',
                      selected: _selectedBillableActivities,
                      itemLabel: (activity) => activity.name,
                      errorText: null,
                      enabled: detailReady,
                      onAdd: () => _pickBillableActivities(billableActivities),
                      onRemove: (activity) => setState(
                          () => _selectedBillableActivities.remove(activity)),
                    ),
                    const SizedBox(height: AppDimensions.cardSpacing),
                    EstimatedDurationInput(
                      label: AppStrings.billableHoursWorkedLabel,
                      hoursController: _billableHoursController,
                      minutesController: _billableMinutesController,
                      secondsController: _billableSecondsController,
                      errorText: _billableHoursError,
                    ),
                    const SizedBox(height: AppDimensions.cardSpacing),
                    MultiSelectChipField<Activity>(
                      label: AppStrings.nonBillableActivitiesLabel,
                      addButtonLabel: AppStrings.activityListAddButton,
                      emptyText: AppStrings.activitiesEmptyForProjectMessage,
                      disabledHintText: 'Loading activities...',
                      selected: _selectedNonBillableActivities,
                      itemLabel: (activity) => activity.name,
                      errorText: null,
                      enabled: detailReady,
                      onAdd: () =>
                          _pickNonBillableActivities(nonBillableActivities),
                      onRemove: (activity) => setState(() =>
                          _selectedNonBillableActivities.remove(activity)),
                    ),
                    const SizedBox(height: AppDimensions.cardSpacing),
                    EstimatedDurationInput(
                      label: AppStrings.nonBillableHoursWorkedLabel,
                      hoursController: _nonBillableHoursController,
                      minutesController: _nonBillableMinutesController,
                      secondsController: _nonBillableSecondsController,
                      errorText: _nonBillableHoursError,
                    ),
                  ],
                );
              }),
            ],
            const SizedBox(height: AppDimensions.cardSpacing),
            Builder(builder: (context) {
              // The pickable window is the current Mon-Sat week (the week
              // locks once Sunday starts), clamped to the module's own
              // start/end dates, and never beyond today.
              final weekMonday = TimesheetValidator.currentWeekMonday();
              final moduleStart = _module?.startDate;
              final firstDate =
                  moduleStart != null && moduleStart.isAfter(weekMonday)
                      ? moduleStart
                      : weekMonday;
              final now = DateTime.now();
              final moduleEnd = _module?.endDate;
              final lastDate = moduleEnd != null && moduleEnd.isBefore(now)
                  ? moduleEnd
                  : now;
              return AppDatePicker(
                label: AppStrings.timesheetFieldWorkDate,
                value: _workDate,
                firstDate: firstDate,
                lastDate: lastDate,
                enabled: _module != null,
                disabledHintText: 'Select a module first',
                selectableDayPredicate: (day) =>
                    day.weekday != DateTime.sunday,
                onChanged: (value) => setState(() => _workDate = value),
                validator: (value) => TimesheetValidator.workDate(
                  value,
                  startDate: _module?.startDate,
                  endDate: _module?.endDate,
                ),
              );
            }),
            const SizedBox(height: AppDimensions.cardSpacing),
            AppTextField(
              controller: _workDoneController,
              label: AppStrings.timesheetFieldWorkDone,
              icon: Icons.description_outlined,
              hintText: AppStrings.timesheetWorkDoneHint,
              maxLines: 4,
              validator: TimesheetValidator.workDone,
            ),
            const SizedBox(height: AppDimensions.sectionSpacing),
            AppButton(
              text: AppStrings.submitTimesheetButton,
              isLoading: workLogViewModel.isSubmitting,
              onPressed: workLogViewModel.isSubmitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
