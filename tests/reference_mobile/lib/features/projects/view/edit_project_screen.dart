import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../model/project_summary.dart';
import '../model/update_project_request.dart';
import '../viewmodel/project_view_model.dart';
import '../widgets/section_header.dart';

/// Edit Project - project-level fields only (Client ID). Project Name and
/// Project ID stay read-only, matching the wireframe; everything else
/// (Team Leader, Employees, Activities, Status, timeline/hours revisions)
/// moved to the module level - see `EditModuleScreen`, reached from a
/// module card on [ProjectDetailsScreen].
class EditProjectScreen extends StatefulWidget {
  final int projectId;

  const EditProjectScreen({super.key, required this.projectId});

  @override
  State<EditProjectScreen> createState() => _EditProjectScreenState();
}

class _EditProjectScreenState extends State<EditProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _clientIdController;

  bool _initialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _clientIdController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProjectViewModel>().fetchProjectDetails(widget.projectId);
    });
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    super.dispose();
  }

  void _prefillFromProject(ProjectSummary project) {
    if (_initialized) return;
    _clientIdController.text = project.clientId ?? '';
    _initialized = true;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final request = UpdateProjectRequest(
      clientId: _clientIdController.text.trim(),
    );

    final result = await context
        .read<ProjectViewModel>()
        .updateProject(widget.projectId, request);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      // Passed through the pop result rather than shown here - popping
      // right after queuing a snackbar clears it before it can render,
      // since SnackbarDismissingObserver wipes the messenger on every
      // route change. The caller shows it once back on a settled screen
      // instead.
      Navigator.pop(context, (message: result.message, isError: false));
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ProjectViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Project'),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(context, viewModel)),
    );
  }

  Widget _buildBody(BuildContext context, ProjectViewModel viewModel) {
    switch (viewModel.detailState) {
      case ProjectLoadState.initial:
      case ProjectLoadState.loading:
        return const AppLoader(message: 'Loading project...');

      case ProjectLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: 'Unable to load project',
          message: viewModel.detailErrorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchProjectDetails(widget.projectId),
        );

      case ProjectLoadState.success:
        final project = viewModel.selectedProject;
        if (project == null) {
          return const AppEmptyView(
            icon: Icons.folder_off_outlined,
            title: 'Project not found',
          );
        }
        _prefillFromProject(project);
        return _buildForm(project);
    }
  }

  Widget _buildForm(ProjectSummary project) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.screenPadding),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Project'),
            const SizedBox(height: AppDimensions.cardSpacing),
            _ReadOnlyField(
              label: 'Project Name',
              icon: Icons.folder_outlined,
              value: project.projectName,
            ),
            const SizedBox(height: AppDimensions.cardSpacing),
            _ReadOnlyField(
              label: 'Project ID',
              icon: Icons.tag,
              value: project.projectCode,
            ),
            const SizedBox(height: AppDimensions.cardSpacing),
            AppTextField(
              controller: _clientIdController,
              label: 'Client ID',
              icon: Icons.badge_outlined,
            ),
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
                    onPressed: _isSaving ? null : _submit,
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
/// used for context (Project Name / Project ID) that this screen shows but
/// never lets the user change, per the wireframe's greyed-out fields.
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
