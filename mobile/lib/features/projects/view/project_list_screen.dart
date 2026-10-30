import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/dialogs/delete_dialog.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../model/project_list_item.dart';
import '../viewmodel/project_view_model.dart';
import '../widgets/project_card.dart';
import 'create_project_screen.dart';
import 'edit_project_screen.dart';
import 'project_details_screen.dart';

/// [ProjectViewModel] is provided app-wide (see main.dart), the same way
/// [AuthViewModel] is, so that state stays in sync across List, Details
/// and Edit screens even though each is pushed as an independent route.
class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final viewModel = context.read<ProjectViewModel>();
      if (viewModel.loadState == ProjectLoadState.initial || viewModel.cacheReadsEnabled) {
        viewModel.fetchProjects();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProjectListItem> _filter(List<ProjectListItem> projects) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return projects;
    return projects.where((project) {
      return project.projectName.toLowerCase().contains(query) ||
          project.projectCode.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openDetails(BuildContext context, ProjectListItem project) async {
    if (!context.canPushRoute) return;
    final result = await Navigator.push<({String message, bool isError})>(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectDetailsScreen(projectId: project.id),
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
    context.read<ProjectViewModel>().fetchProjects();
  }

  Future<void> _openCreateProject(BuildContext context) async {
    if (!context.canPushRoute) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateProjectScreen()),
    );
    if (!context.mounted) return;
    context.read<ProjectViewModel>().fetchProjects();
  }

  Future<void> _openEdit(BuildContext context, ProjectListItem project) async {
    if (!context.canPushRoute) return;
    final result = await Navigator.push<({String message, bool isError})>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProjectScreen(projectId: project.id),
      ),
    );
    if (!context.mounted) return;
    context.read<ProjectViewModel>().fetchProjects();
    if (result != null) {
      if (result.isError) {
        SnackbarUtil.showError(context, result.message);
      } else {
        SnackbarUtil.showSuccess(context, result.message);
      }
    }
  }

  Future<void> _handleDeactivate(
    BuildContext context,
    ProjectListItem project,
  ) async {
    // Resolved up front, before any `await` - this list item's `context`
    // can go stale by the time the API call finishes (the list re-sorts as
    // soon as `ProjectViewModel.deactivateProject` refetches), which would
    // otherwise silently swallow the result snackbar even though the
    // deactivation itself succeeded.
    final messenger = ScaffoldMessenger.of(context);
    final viewModel = context.read<ProjectViewModel>();

    final confirmed = await DeleteDialog.show(
      context,
      title: 'Deactivate Project',
      message: 'Are you sure you want to deactivate "${project.projectName}"? '
          'It will stay in the list marked as inactive.',
      confirmLabel: 'Deactivate',
    );

    if (!confirmed) return;

    final result = await viewModel.deactivateProject(project.id);

    if (result.success) {
      SnackbarUtil.showSuccessOn(messenger, result.message);
    } else {
      SnackbarUtil.showErrorOn(messenger, result.message);
    }
  }

  Future<void> _handleActivate(
    BuildContext context,
    ProjectListItem project,
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
    } else {
      SnackbarUtil.showErrorOn(messenger, result.message);
    }
  }

  Future<void> _handleDelete(
    BuildContext context,
    ProjectListItem project,
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

    if (!confirmed) return;

    final result = await viewModel.deleteProject(project.id);

    if (result.success) {
      SnackbarUtil.showSuccessOn(messenger, result.message);
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
        title: const Text('Projects'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search projects by name or code',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody(context, viewModel, canManage)),
          ],
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateProject(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Project'),
            )
          : null,
    );
  }

  Widget _buildBody(
    BuildContext context,
    ProjectViewModel viewModel,
    bool canManage,
  ) {
    switch (viewModel.loadState) {
      case ProjectLoadState.initial:
      case ProjectLoadState.loading:
        return const AppLoader(message: 'Loading projects...');

      case ProjectLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: 'Unable to load projects',
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchProjects(),
        );

      case ProjectLoadState.success:
        if (viewModel.projects.isEmpty) {
          return const AppEmptyView(
            icon: Icons.folder_open_outlined,
            title: 'No projects yet',
            message: 'Tap "Create Project" to create your first project.',
          );
        }

        final filtered = _filter(viewModel.projects);

        if (filtered.isEmpty) {
          return const AppEmptyView(
            icon: Icons.search_off_outlined,
            title: 'No matching projects',
            message: 'Try a different name or code.',
          );
        }

        return RefreshIndicator(
          onRefresh: () => viewModel.fetchProjects(force: true),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            itemCount: filtered.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final project = filtered[index];
              return ProjectCard(
                project: project,
                canManage: canManage,
                onTap: () => _openDetails(context, project),
                onEdit: () => _openEdit(context, project),
                onDeactivate: () => _handleDeactivate(context, project),
                onActivate: () => _handleActivate(context, project),
                onDelete: () => _handleDelete(context, project),
              );
            },
          ),
        );
    }
  }
}
