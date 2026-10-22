import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/dialogs/delete_dialog.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../model/activity.dart';
import '../viewmodel/activity_view_model.dart';
import '../widgets/activity_card.dart';

/// Project Controller-only master list of Activities (see the backend's
/// `@PreAuthorize` on `/api/activities/**`) - a Project Controller creates
/// activities here, then assigns them per-project as Billable/Non-Billable
/// in Create/Edit Project. [ActivityViewModel] is provided app-wide (see
/// main.dart) so the Project create/edit pickers see newly-created
/// activities without a separate refetch.
class ActivityListScreen extends StatefulWidget {
  const ActivityListScreen({super.key});

  @override
  State<ActivityListScreen> createState() => _ActivityListScreenState();
}

class _ActivityListScreenState extends State<ActivityListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ActivityViewModel>().fetchActivities();
    });
  }

  Future<void> _openAddActivity(BuildContext context) async {
    if (!context.canPushRoute) return;

    final controller = TextEditingController();
    final viewModel = context.read<ActivityViewModel>();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(AppStrings.addActivityTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: AppStrings.activityFieldName,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (name == null || name.isEmpty || !context.mounted) return;

    final result = await viewModel.createActivity(name);
    if (!context.mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, AppStrings.activityCreateSuccess);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  Future<void> _handleDelete(BuildContext context, Activity activity) async {
    final messenger = ScaffoldMessenger.of(context);
    final viewModel = context.read<ActivityViewModel>();

    final confirmed = await DeleteDialog.show(
      context,
      title: AppStrings.activityDeleteTitle,
      message: AppStrings.activityDeleteConfirmMessage(activity.name),
    );

    if (!confirmed) return;

    final result = await viewModel.deleteActivity(activity.id);

    if (result.success) {
      SnackbarUtil.showSuccessOn(messenger, result.message);
    } else {
      SnackbarUtil.showErrorOn(messenger, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ActivityViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.activityListTitle),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(context, viewModel)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddActivity(context),
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.activityListAddButton),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ActivityViewModel viewModel) {
    switch (viewModel.loadState) {
      case ActivityLoadState.initial:
      case ActivityLoadState.loading:
        return const AppLoader(message: AppStrings.activityListLoading);

      case ActivityLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.activityListLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchActivities(),
        );

      case ActivityLoadState.success:
        if (viewModel.activities.isEmpty) {
          return const AppEmptyView(
            icon: Icons.checklist_outlined,
            title: AppStrings.activityListEmptyTitle,
            message: AppStrings.activityListEmptyMessage,
          );
        }

        return RefreshIndicator(
          onRefresh: viewModel.fetchActivities,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppDimensions.screenPadding,
              AppDimensions.screenPadding,
              AppDimensions.screenPadding,
              88,
            ),
            itemCount: viewModel.activities.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final Activity activity = viewModel.activities[index];
              return ActivityCard(
                activity: activity,
                onDelete: () => _handleDelete(context, activity),
              );
            },
          ),
        );
    }
  }
}
