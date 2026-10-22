import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/dialogs/delete_dialog.dart';
import '../../../shared/enums/project_status.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/files_screen.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../../modules/view/module_details_screen.dart';
import '../../modules/widgets/module_card.dart';
import '../model/project_summary.dart';
import '../viewmodel/project_view_model.dart';
import '../widgets/project_action_bar.dart';
import 'edit_project_screen.dart';

/// Read-only "Project Database" view (see the wireframe's Project Database
/// screen) - project identity plus its module list. Always fetches fresh
/// data from `GET /projects/{id}` rather than trusting whatever the caller
/// had cached in the list.
class ProjectDetailsScreen extends StatefulWidget {
  final int projectId;

  const ProjectDetailsScreen({super.key, required this.projectId});

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProjectViewModel>().fetchProjectDetails(widget.projectId);
    });
  }

  void _refresh(BuildContext context) {
    context.read<ProjectViewModel>().fetchProjectDetails(widget.projectId, force: true);
  }

  Future<void> _openEdit(BuildContext context) async {
    if (!context.canPushRoute) return;
    final result = await Navigator.push<({String message, bool isError})>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProjectScreen(projectId: widget.projectId),
      ),
    );
    if (!context.mounted) return;
    _refresh(context);
    if (result != null) {
      if (result.isError) {
        SnackbarUtil.showError(context, result.message);
      } else {
        SnackbarUtil.showSuccess(context, result.message);
      }
    }
  }

  Future<void> _openModuleDetails(BuildContext context, int moduleId) async {
    if (!context.canPushRoute) return;
    final result = await Navigator.push<({String message, bool isError})>(
      context,
      MaterialPageRoute(
        builder: (_) => ModuleDetailsScreen(moduleId: moduleId),
      ),
    );
    if (!context.mounted) return;
    if (result != null) {
      if (result.isError) {
        SnackbarUtil.showError(context, result.message);
      } else {
        SnackbarUtil.showSuccess(context, result.message);
      }
    }
    _refresh(context);
  }

  Future<void> _handleDeactivate(
    BuildContext context,
    ProjectSummary project,
  ) async {
    // Resolved up front, before any `await` - see the identical note on
    // `ProjectListScreen._handleDeactivate`.
    final messenger = ScaffoldMessenger.of(context);
    final viewModel = context.read<ProjectViewModel>();

    final confirmed = await DeleteDialog.show(
      context,
      title: 'Deactivate Project',
      message: 'Are you sure you want to deactivate "${project.projectName}"? '
          'It will stay in the list marked as inactive, along with every one '
          'of its modules.',
      confirmLabel: 'Deactivate',
    );

    if (!confirmed) return;

    final result = await viewModel.deactivateProject(project.id);

    if (result.success) {
      SnackbarUtil.showSuccessOn(messenger, result.message);
      if (context.mounted) _refresh(context);
    } else {
      SnackbarUtil.showErrorOn(messenger, result.message);
    }
  }

  Future<void> _handleActivate(
    BuildContext context,
    ProjectSummary project,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final viewModel = context.read<ProjectViewModel>();

    final confirmed = await DeleteDialog.show(
      context,
      title: 'Activate Project',
      message: 'Reactivate "${project.projectName}"? Its modules will stay '
          'inactive until you activate each one individually.',
      confirmLabel: 'Activate',
    );

    if (!confirmed) return;

    final result = await viewModel.activateProject(project.id);

    if (result.success) {
      SnackbarUtil.showSuccessOn(messenger, result.message);
      if (context.mounted) _refresh(context);
    } else {
      SnackbarUtil.showErrorOn(messenger, result.message);
    }
  }

  Future<void> _handleDelete(
    BuildContext context,
    ProjectSummary project,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final viewModel = context.read<ProjectViewModel>();

    final confirmed = await DeleteDialog.show(
      context,
      title: 'Delete Project',
      message: 'Are you sure you want to delete "${project.projectName}"? '
          'This cannot be undone.',
      confirmLabel: 'Delete',
    );

    if (!confirmed || !context.mounted) return;

    final result = await viewModel.deleteProject(project.id);

    if (result.success) {
      // Passed through the pop result rather than shown here - popping
      // right after queuing a snackbar clears it before it can render,
      // since SnackbarDismissingObserver wipes the messenger on every route
      // change. The caller (ProjectListScreen._openDetails) shows it once
      // back on a settled screen instead.
      if (context.mounted) {
        Navigator.pop(context, (message: result.message, isError: false));
      }
    } else {
      SnackbarUtil.showErrorOn(messenger, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ProjectViewModel>();
    final role = context.watch<AuthViewModel>().role;
    final canManage = role == UserRole.projectManager;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Details'),
        actions: [IconButton(tooltip: 'Attachments', icon: const Icon(Icons.attach_file), onPressed: () {
          if (!context.canPushRoute) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => FilesScreen(
            targetId: widget.projectId,
            categories: {'project_attachment':'Project attachments', if (role == UserRole.captain || role == UserRole.projectManager) 'billing_document':'Billing documents'},
          )));
        })],
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(context, viewModel, canManage)),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ProjectViewModel viewModel,
    bool canManage,
  ) {
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
          onAction: () =>
              viewModel.fetchProjectDetails(widget.projectId),
        );

      case ProjectLoadState.success:
        final project = viewModel.selectedProject;
        if (project == null) {
          return const AppEmptyView(
            icon: Icons.folder_off_outlined,
            title: 'Project not found',
          );
        }
        return _buildDetails(context, project, canManage);
    }
  }

  Widget _buildDetails(
    BuildContext context,
    ProjectSummary project,
    bool canManage,
  ) {
    final status = ProjectStatusX.fromApiValue(project.status);
    // Total Hours Utilized is meaningless before work can even start (Not
    // Started) or once the project is deactivated, so it's hidden for those
    // two states only - every other field on this card stays unconditional
    // on status, same as before.
    final showWorkedHours = status != ProjectStatus.notStarted &&
        status != ProjectStatus.inactive;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        project.projectName,
                        style: AppTextStyles.heading.copyWith(fontSize: 20),
                      ),
                    ),
                    _StatusChip(status: ProjectStatusX.fromApiValue(project.status)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Project ID: ${project.projectCode}'),
                if (project.clientId != null && project.clientId!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('Client ID: ${project.clientId}'),
                ],
                if (project.startDate != null) ...[
                  const SizedBox(height: 2),
                  Text('Start Date: ${DateFormatter.format(project.startDate!)}'),
                ],
                if (project.endDate != null) ...[
                  const SizedBox(height: 2),
                  Text('End Date: ${DateFormatter.format(project.endDate!)}'),
                ],
                if (project.estimatedMinutes != null) ...[
                  const SizedBox(height: 2),
                  Text('Estimated Hours: ${DurationFormatter.humanReadable(project.estimatedMinutes)}'),
                ],
                if (showWorkedHours && project.workedMinutes != null) ...[
                  const SizedBox(height: 2),
                  Text('Total Hours Utilized: ${DurationFormatter.humanReadable(project.workedMinutes)}'),
                ],
                if (project.pendingMinutes != null) ...[
                  const SizedBox(height: 2),
                  Text('Pending Hours: ${DurationFormatter.humanReadable(project.pendingMinutes)}'),
                ],
              ],
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 16),
            ProjectActionBar(
              isActive: project.isActive,
              onEdit: () => _openEdit(context),
              onDeactivate: () => _handleDeactivate(context, project),
              onActivate: () => _handleActivate(context, project),
              onDelete: () => _handleDelete(context, project),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Modules',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (project.modules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No modules yet.'),
            )
          else
            for (final module in project.modules) ...[
              ModuleCard(
                module: module,
                onTap: () => _openModuleDetails(context, module.id),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ProjectStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontWeight: FontWeight.w600, color: status.color),
      ),
    );
  }
}
