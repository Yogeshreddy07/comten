import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../modules/model/module_list_item.dart';
import '../viewmodel/reason_for_delay_view_model.dart';

/// Team Lead's Reason for Delay screen - submits a delay reason for a led
/// project, which notifies every Project Controller (see
/// `NotificationServiceImpl#submitDelayRequest`). Hosts its own
/// [ReasonForDelayViewModel] (not provided app-wide) since this screen is
/// the only place that state is needed.
class ReasonForDelayScreen extends StatelessWidget {
  const ReasonForDelayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ReasonForDelayViewModel>(
      create: (_) => ReasonForDelayViewModel(
        moduleRepository: DependencyInjection.moduleRepository,
        notificationRepository: DependencyInjection.notificationRepository,
      ),
      child: const _ReasonForDelayView(),
    );
  }
}

class _ReasonForDelayView extends StatefulWidget {
  const _ReasonForDelayView();

  @override
  State<_ReasonForDelayView> createState() => _ReasonForDelayViewState();
}

class _ReasonForDelayViewState extends State<_ReasonForDelayView> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  int? _projectId;
  ModuleListItem? _module;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReasonForDelayViewModel>().fetchLedModules();
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _selectProject(_ProjectOption? project) {
    setState(() {
      _projectId = project?.id;
      _module = null;
    });
  }

  void _selectModule(ModuleListItem? module) {
    setState(() => _module = module);
  }

  Future<void> _submit() async {
    if (context.read<ReasonForDelayViewModel>().isSubmitting) return;
    if (_projectId == null) {
      SnackbarUtil.showError(context, AppStrings.reasonForDelaySelectProjectMessage);
      return;
    }
    final module = _module;
    if (module == null) {
      SnackbarUtil.showError(context, AppStrings.reasonForDelaySelectModuleMessage);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final viewModel = context.read<ReasonForDelayViewModel>();
    final result = await viewModel.submitDelayRequest(
      module.id,
      _reasonController.text.trim(),
    );
    if (!mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, AppStrings.reasonForDelaySuccess);
      setState(() {
        _projectId = null;
        _module = null;
        _reasonController.clear();
      });
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ReasonForDelayViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.reasonForDelayTitle),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(viewModel)),
    );
  }

  Widget _buildBody(ReasonForDelayViewModel viewModel) {
    switch (viewModel.loadState) {
      case ReasonForDelayLoadState.initial:
      case ReasonForDelayLoadState.loading:
        return const AppLoader(message: AppStrings.reasonForDelayLoading);

      case ReasonForDelayLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.reasonForDelayLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchLedModules(),
        );

      case ReasonForDelayLoadState.success:
        if (viewModel.ledModules.isEmpty) {
          return const AppEmptyView(
            icon: Icons.folder_off_outlined,
            title: AppStrings.reasonForDelayEmptyTitle,
            message: AppStrings.reasonForDelayEmptyMessage,
          );
        }
        return _buildForm(viewModel);
    }
  }

  Widget _buildForm(ReasonForDelayViewModel viewModel) {
    // Distinct projects across the modules this Team Lead leads - picked
    // first, then the Module dropdown below is scoped to that project,
    // mirroring the Status Update form's Project -> Module flow.
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppDropdown<_ProjectOption>(
              label: AppStrings.reasonForDelayFieldProject,
              icon: Icons.folder_outlined,
              value: selectedProject,
              items: projects,
              itemLabel: (project) => project.name,
              onChanged: _selectProject,
            ),
            if (_projectId != null) ...[
              const SizedBox(height: AppDimensions.cardSpacing),
              AppDropdown<ModuleListItem>(
                label: AppStrings.reasonForDelayFieldModule,
                icon: Icons.widgets_outlined,
                value: matchedModule,
                items: projectModules,
                itemLabel: (module) => module.moduleName,
                onChanged: _selectModule,
                emptyHint: AppStrings.reasonForDelayModulesEmptyHint,
              ),
            ],
            const SizedBox(height: AppDimensions.cardSpacing),
            AppTextField(
              controller: _reasonController,
              label: AppStrings.reasonForDelayFieldReason,
              icon: Icons.report_problem_outlined,
              hintText: AppStrings.reasonForDelayReasonHint,
              maxLines: 5,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? AppStrings.reasonForDelayReasonRequired
                  : null,
            ),
            const SizedBox(height: AppDimensions.sectionSpacing),
            AppButton(
              text: AppStrings.reasonForDelayButton,
              isLoading: viewModel.isSubmitting,
              onPressed: viewModel.isSubmitting ? null : _submit,
            ),
          ],
        ),
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
