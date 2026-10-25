import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/dialogs/delete_dialog.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../model/employee.dart';
import '../viewmodel/employee_view_model.dart';
import '../widgets/employee_card.dart';
import 'add_edit_employee_screen.dart';

/// Staff directory for Captains / Project Controllers (the wireframe's
/// "Employe Management" screen). [EmployeeViewModel] is provided app-wide
/// (see main.dart) so the list stays in sync after Add/Edit screens pop.
/// Reachable only from the Captain / Project Controller dashboards, matching
/// the backend's @PreAuthorize on `/api/employees/**`.
///
/// Pass [roleFilter] to scope this same screen to a single role instead of
/// the Employee/Team Leader directory - the Captain dashboard's "Project Controller
/// Management" tile reuses this screen with `roleFilter:
/// UserRole.projectManager` rather than duplicating it, and locks the new
/// employee's role to match (see [AddEditEmployeeScreen.fixedRole]).
class EmployeeListScreen extends StatefulWidget {
  final UserRole? roleFilter;
  final String? title;
  final String? addButtonLabel;
  final String? emptyTitle;
  final String? emptyMessage;

  const EmployeeListScreen({
    super.key,
    this.roleFilter,
    this.title,
    this.addButtonLabel,
    this.emptyTitle,
    this.emptyMessage,
  });

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Always refresh on entry: another admin may have changed staff since
      // the last visit, and stale isActive flags are misleading here.
      context.read<EmployeeViewModel>().fetchEmployees(roleFilter: widget.roleFilter);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Employee> _filter(List<Employee> employees) {
    employees = employees.where((employee) => widget.roleFilter != null
        ? employee.role == widget.roleFilter
        : [UserRole.employee, UserRole.teamLeader].contains(employee.role)).toList();
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return employees;
    return employees.where((employee) {
      return employee.name.toLowerCase().contains(query) ||
          employee.employeeCode.toLowerCase().contains(query) ||
          employee.email.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openAdd(BuildContext context) async {
    if (!context.canPushRoute) return;
    final message = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditEmployeeScreen(fixedRole: widget.roleFilter),
      ),
    );
    // The add/edit flow pops its success message up here once the save
    // landed; show it now, on this list screen and after every pop, instead
    // of deeper in the flow where the SnackbarDismissingObserver would clear
    // it the moment the route changed.
    if (message != null && message.isNotEmpty && context.mounted) {
      SnackbarUtil.showSuccess(context, message);
    }
  }

  Future<void> _openEdit(BuildContext context, Employee employee) async {
    if (!context.canPushRoute) return;
    final message = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditEmployeeScreen(
          employee: employee,
          fixedRole: widget.roleFilter,
        ),
      ),
    );
    if (message != null && message.isNotEmpty && context.mounted) {
      SnackbarUtil.showSuccess(context, message);
    }
  }

  Future<void> _handleDeactivate(
    BuildContext context,
    Employee employee,
  ) async {
    final confirmed = await DeleteDialog.show(
      context,
      title: AppStrings.deactivateEmployeeTitle,
      message: AppStrings.deactivateEmployeeMessage(employee.name),
      confirmLabel: 'Deactivate',
    );

    if (!confirmed || !context.mounted) return;

    final result =
        await context.read<EmployeeViewModel>().deactivateEmployee(employee.id);

    if (!context.mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  Future<void> _handleActivate(
    BuildContext context,
    Employee employee,
  ) async {
    final confirmed = await DeleteDialog.show(
      context,
      title: AppStrings.activateEmployeeTitle,
      message: AppStrings.activateEmployeeMessage(employee.name),
      confirmLabel: 'Activate',
    );

    if (!confirmed || !context.mounted) return;

    final result =
        await context.read<EmployeeViewModel>().activateEmployee(employee.id);

    if (!context.mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  Future<void> _handleDelete(
    BuildContext context,
    Employee employee,
  ) async {
    final confirmed = await DeleteDialog.show(
      context,
      title: AppStrings.deleteEmployeeTitle,
      message: AppStrings.deleteEmployeeMessage(employee.name),
    );

    if (!confirmed || !context.mounted) return;

    final result =
        await context.read<EmployeeViewModel>().deleteEmployee(employee.id);

    if (!context.mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EmployeeViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? AppStrings.employeeListTitle),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(context, viewModel)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAdd(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(widget.addButtonLabel ?? AppStrings.employeeListAddButton),
      ),
    );
  }

  Widget _buildBody(BuildContext context, EmployeeViewModel viewModel) {
    switch (viewModel.loadState) {
      case EmployeeLoadState.initial:
      case EmployeeLoadState.loading:
        return const AppLoader(message: AppStrings.employeeListLoading);

      case EmployeeLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.employeeListLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchEmployees(roleFilter: widget.roleFilter),
        );

      case EmployeeLoadState.success:
        if (_query.trim().isEmpty && _filter(viewModel.employees).isEmpty) {
          return AppEmptyView(
            icon: Icons.people_outline,
            title: widget.emptyTitle ?? AppStrings.employeeListEmptyTitle,
            message: widget.emptyMessage ?? AppStrings.employeeListEmptyMessage,
          );
        }

        final filtered = _filter(viewModel.employees);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                AppDimensions.screenPadding,
                AppDimensions.screenPadding,
                8,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: AppStrings.employeeListSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.inputRadius),
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? AppEmptyView(
                      icon: Icons.person_search_outlined,
                      title: 'No matching employees',
                      message: 'Try a different name, ID, or email.',
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          viewModel.fetchEmployees(roleFilter: widget.roleFilter),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimensions.screenPadding,
                          8,
                          AppDimensions.screenPadding,
                          88,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final employee = filtered[index];
                          return EmployeeCard(
                            employee: employee,
                            onEdit: () => _openEdit(context, employee),
                            onDeactivate: () =>
                                _handleDeactivate(context, employee),
                            onActivate: () =>
                                _handleActivate(context, employee),
                            onDelete: () => _handleDelete(context, employee),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
    }
  }
}
