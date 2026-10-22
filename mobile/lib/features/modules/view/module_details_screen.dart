import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/dialogs/delete_dialog.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/enums/project_status.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../approvals/model/project_change_request.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../../projects/widgets/project_action_bar.dart';
import '../../projects/widgets/review_summary_card.dart';
import '../model/module_summary.dart';
import '../viewmodel/module_view_model.dart';
import 'edit_module_screen.dart';

/// Trims a trailing ".0" so a whole-number area shows as "1200" rather than
/// "1200.0".
String _formatArea(double value) {
  return value == value.truncateToDouble()
      ? value.truncate().toString()
      : value.toString();
}

/// Read-only "Module Database" view, reached by tapping a module card on
/// [ProjectDetailsScreen] - always fetches fresh data from
/// `GET /modules/{id}` rather than trusting whatever the caller had cached
/// in the list, since a list row doesn't carry team members.
class ModuleDetailsScreen extends StatefulWidget {
  final int moduleId;

  const ModuleDetailsScreen({super.key, required this.moduleId});

  @override
  State<ModuleDetailsScreen> createState() => _ModuleDetailsScreenState();
}

class _ModuleDetailsScreenState extends State<ModuleDetailsScreen> {
  bool _hasPendingChangeRequest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ModuleViewModel>().fetchModuleDetails(widget.moduleId);
      _loadPendingChangeRequest();
    });
  }

  Future<void> _loadPendingChangeRequest() async {
    final result = await DependencyInjection.approvalRepository
        .getChangeRequestsForModule(widget.moduleId);
    if (!mounted || !result.success) return;
    final requests = (result.data as List<ProjectChangeRequest>?) ?? [];
    setState(() {
      _hasPendingChangeRequest =
          requests.any((r) => r.effectiveStatus == ApprovalStatus.pending);
    });
  }

  Future<void> _openEdit(BuildContext context) async {
    if (!context.canPushRoute) return;
    final result = await Navigator.push<({String message, bool isError})>(
      context,
      MaterialPageRoute(
        builder: (_) => EditModuleScreen(moduleId: widget.moduleId),
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
    context.read<ModuleViewModel>().fetchModuleDetails(widget.moduleId);
  }

  Future<void> _handleDeactivate(
    BuildContext context,
    ModuleSummary module,
  ) async {
    final confirmed = await DeleteDialog.show(
      context,
      title: 'Deactivate Module',
      message: 'Are you sure you want to deactivate "${module.moduleName}"? '
          'It will stay in the list marked as inactive.',
      confirmLabel: 'Deactivate',
    );

    if (!confirmed || !context.mounted) return;

    final viewModel = context.read<ModuleViewModel>();
    final result = await viewModel.deactivateModule(module.id);

    if (!context.mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  Future<void> _handleActivate(
    BuildContext context,
    ModuleSummary module,
  ) async {
    final confirmed = await DeleteDialog.show(
      context,
      title: 'Activate Module',
      message: 'Reactivate "${module.moduleName}"? It will return to the '
          'status it had before deactivation.',
      confirmLabel: 'Activate',
    );

    if (!confirmed || !context.mounted) return;

    final viewModel = context.read<ModuleViewModel>();
    final result = await viewModel.activateModule(module.id);

    if (!context.mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);
      viewModel.fetchModuleDetails(module.id);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  Future<void> _handleDelete(
    BuildContext context,
    ModuleSummary module,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final viewModel = context.read<ModuleViewModel>();

    final confirmed = await DeleteDialog.show(
      context,
      title: 'Delete Module',
      message: 'Are you sure you want to delete "${module.moduleName}"? '
          'This cannot be undone.',
      confirmLabel: 'Delete',
    );

    if (!confirmed || !context.mounted) return;

    final result = await viewModel.deleteModule(module.id);

    if (!context.mounted) return;

    if (result.success) {
      // Passed through the pop result rather than shown here - see the
      // identical note on ProjectDetailsScreen._handleDelete: popping right
      // after queuing a snackbar clears it before it can render, since
      // SnackbarDismissingObserver wipes the messenger on every route
      // change. The caller shows it once back on a settled screen instead.
      Navigator.pop(context, (message: result.message, isError: false));
    } else {
      SnackbarUtil.showErrorOn(messenger, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ModuleViewModel>();
    final role = context.watch<AuthViewModel>().role;
    final canManage = role == UserRole.projectManager;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.moduleDetailsTitle),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(context, viewModel, canManage)),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ModuleViewModel viewModel,
    bool canManage,
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
        return _buildDetails(context, module, canManage);
    }
  }

  Widget _buildDetails(
    BuildContext context,
    ModuleSummary module,
    bool canManage,
  ) {
    final status = ProjectStatusX.fromApiValue(module.status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
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
                        module.moduleName,
                        style: AppTextStyles.heading.copyWith(fontSize: 20),
                      ),
                    ),
                    _StatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${module.projectName} (${module.projectCode})'),
              ],
            ),
          ),
          if (_hasPendingChangeRequest) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fact_check_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(AppStrings.projectPendingApprovalBadge)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          ReviewSummarySection(
            title: 'Team',
            rows: [
              ReviewDetailRow('Team Leader', module.teamLeadName ?? '-'),
              ReviewDetailRow(
                'Team Members',
                module.memberNames.isEmpty ? '-' : module.memberNames.join(', '),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ReviewSummarySection(
            title: 'Timeline & Hours',
            rows: [
              ReviewDetailRow(
                'Start Date',
                DateFormatter.formatNullable(module.startDate) ?? '-',
              ),
              ReviewDetailRow(
                'End Date',
                DateFormatter.formatNullable(module.endDate) ?? '-',
              ),
              ReviewDetailRow(
                'Working Hours Estimated',
                DurationFormatter.humanReadable(module.estimatedMinutes) ?? '0 minutes',
              ),
              ReviewDetailRow(
                'Working Hours Completed',
                DurationFormatter.humanReadable(module.completedMinutes) ??
                    '${module.completedHours ?? 0} hrs',
              ),
              ReviewDetailRow(
                'Working Hours Remaining',
                DurationFormatter.humanReadable(module.remainingMinutes) ?? '0 minutes',
              ),
              ReviewDetailRow('Status', status.label),
            ],
          ),
          const SizedBox(height: 16),
          ReviewSummarySection(
            title: 'Building Details',
            rows: [
              ReviewDetailRow(
                'Building Classification',
                module.buildingClassification ?? '-',
              ),
              ReviewDetailRow(
                'Structure Classification',
                module.structureClassification ?? '-',
              ),
              ReviewDetailRow(
                'Number of Floors',
                module.numberOfFloors?.toString() ?? '-',
              ),
              ReviewDetailRow(
                'Area',
                module.area != null ? '${_formatArea(module.area!)} sq ft' : '-',
              ),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: 24),
            ProjectActionBar(
              isActive: status != ProjectStatus.inactive,
              isCancelled: status == ProjectStatus.cancelled,
              onEdit: () => _openEdit(context),
              onDeactivate: () => _handleDeactivate(context, module),
              onActivate: () => _handleActivate(context, module),
              onDelete: () => _handleDelete(context, module),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ProjectStatus status;

  const _StatusBadge({required this.status});

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
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: status.color,
        ),
      ),
    );
  }
}
