import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/project_work_stage.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../modules/model/module_list_item.dart';
import '../viewmodel/status_update_view_model.dart';

/// Team Lead's Status Update screen - toggles a led project between WIP and
/// Billing (see `ProjectServiceImpl#updateWorkStage`). Selecting Billing
/// makes the project appear in the Project Controller's Billing Status
/// list; switching back to WIP removes it. Hosts its own
/// [StatusUpdateViewModel] (not provided app-wide) since this screen is the
/// only place that state is needed.
class StatusUpdateScreen extends StatelessWidget {
  const StatusUpdateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StatusUpdateViewModel>(
      create: (_) => StatusUpdateViewModel(
        repository: DependencyInjection.moduleRepository,
      ),
      child: const _StatusUpdateView(),
    );
  }
}

class _StatusUpdateView extends StatefulWidget {
  const _StatusUpdateView();

  @override
  State<_StatusUpdateView> createState() => _StatusUpdateViewState();
}

class _StatusUpdateViewState extends State<_StatusUpdateView> {
  int? _projectId;
  ModuleListItem? _module;

  /// Deliberately null until the Team Lead picks one - the Status dropdown
  /// must not pre-select WIP (or anything else) as a default.
  ProjectWorkStage? _stage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StatusUpdateViewModel>().fetchLedModules();
    });
  }

  void _selectProject(_ProjectOption? project) {
    setState(() {
      _projectId = project?.id;
      _module = null;
      _stage = null;
    });
  }

  void _selectModule(ModuleListItem? module) {
    setState(() {
      _module = module;
      _stage = null;
    });
  }

  Future<void> _submit() async {
    if (context.read<StatusUpdateViewModel>().isSaving) return;
    final module = _module;
    if (_projectId == null) {
      SnackbarUtil.showError(context, AppStrings.statusUpdateSelectProjectMessage);
      return;
    }
    if (module == null) {
      SnackbarUtil.showError(context, AppStrings.statusUpdateSelectModuleMessage);
      return;
    }
    final stage = _stage;
    if (stage == null) {
      SnackbarUtil.showError(context, AppStrings.statusUpdateSelectStatusMessage);
      return;
    }

    final viewModel = context.read<StatusUpdateViewModel>();
    final result = await viewModel.updateWorkStage(module.id, stage.apiValue);
    if (!mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, AppStrings.statusUpdateSuccess);
      // Force a deliberate re-selection before another submit is possible -
      // otherwise Submit stays enabled with the same stage still chosen, and
      // an accidental repeat click would just resurface the backend's
      // already-in-this-stage error right after a success message.
      setState(() => _stage = null);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<StatusUpdateViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.statusUpdateTitle),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(viewModel)),
    );
  }

  Widget _buildBody(StatusUpdateViewModel viewModel) {
    switch (viewModel.loadState) {
      case StatusUpdateLoadState.initial:
      case StatusUpdateLoadState.loading:
        return const AppLoader(message: AppStrings.statusUpdateLoading);

      case StatusUpdateLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.statusUpdateLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchLedModules(),
        );

      case StatusUpdateLoadState.success:
        if (viewModel.ledModules.isEmpty) {
          return const AppEmptyView(
            icon: Icons.folder_off_outlined,
            title: AppStrings.statusUpdateEmptyTitle,
            message: AppStrings.statusUpdateEmptyMessage,
          );
        }
        return _buildForm(viewModel);
    }
  }

  Widget _buildForm(StatusUpdateViewModel viewModel) {
    // Distinct projects across the modules this Team Lead leads - picked
    // first, then the Module dropdown below is scoped to that project,
    // mirroring the Work Log form's Project -> Module flow.
    final projectsById = <int, _ProjectOption>{};
    for (final module in viewModel.ledModules) {
      projectsById.putIfAbsent(
        module.projectId,
        () => _ProjectOption(module.projectId, module.projectName),
      );
    }
    final projects = projectsById.values.toList();
    final selectedProject = projectsById[_projectId];

    final projectModules = _projectId != null
        ? viewModel.ledModules.where((m) => m.projectId == _projectId).toList()
        : const <ModuleListItem>[];
    final selected = _module;
    final matchedModule = selected != null &&
            projectModules.any((m) => m.id == selected.id)
        ? projectModules.firstWhere((m) => m.id == selected.id)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppDropdown<_ProjectOption>(
            label: AppStrings.statusUpdateFieldProject,
            icon: Icons.folder_outlined,
            value: selectedProject,
            items: projects,
            itemLabel: (project) => project.name,
            onChanged: _selectProject,
          ),
          if (_projectId != null) ...[
            const SizedBox(height: AppDimensions.cardSpacing),
            AppDropdown<ModuleListItem>(
              label: AppStrings.statusUpdateFieldModule,
              icon: Icons.widgets_outlined,
              value: matchedModule,
              items: projectModules,
              itemLabel: (module) => module.moduleName,
              onChanged: _selectModule,
              emptyHint: AppStrings.statusUpdateModulesEmptyHint,
            ),
          ],
          const SizedBox(height: AppDimensions.cardSpacing),
          AppDropdown<ProjectWorkStage>(
            label: AppStrings.statusUpdateFieldStatus,
            icon: Icons.flag_outlined,
            value: _stage,
            items: ProjectWorkStage.values,
            itemLabel: (stage) => stage.label,
            onChanged: (value) => setState(() => _stage = value),
          ),
          const SizedBox(height: AppDimensions.sectionSpacing),
          AppButton(
            text: AppStrings.statusUpdateButton,
            isLoading: viewModel.isSaving,
            onPressed: viewModel.isSaving ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// Distinct project entry for the first-level dropdown - equality by [id] so
/// the dropdown's value matching survives the list being rebuilt.
class _ProjectOption {
  final int id;
  final String name;

  const _ProjectOption(this.id, this.name);

  @override
  bool operator ==(Object other) => other is _ProjectOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
