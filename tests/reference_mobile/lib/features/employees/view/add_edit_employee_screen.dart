import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../auth/model/api_result.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../model/create_employee_request.dart';
import '../model/employee.dart';
import '../model/update_employee_request.dart';
import '../viewmodel/employee_view_model.dart';
import 'review_employee_screen.dart';

/// Single form for both adding and editing an employee (the wireframe's
/// "Employe Management - Addition" screen). Pass [employee] to edit;
/// omit it to add. On add, the backend generates a temporary password and
/// emails it to the new employee - no password field exists here by design.
///
/// Pass [fixedRole] when this screen is reached from a role-scoped list
/// (the Captain's Project Controller Management screen) - the Role field
/// becomes read-only and locked to that value, since that screen's whole
/// purpose is managing accounts of exactly one role.
///
/// Form state is page-local (plain setState) per the project convention;
/// the actual mutations go through [EmployeeViewModel].
///
/// Tapping "Next" pushes [ReviewEmployeeScreen] with the entered values
/// instead of saving directly. This screen's State stays alive underneath
/// it (a plain Navigator.push, not a replace), so tapping "Edit" there is
/// just a pop back to this same still-populated form; only a "Confirm" +
/// dialog "Save" on the review screen actually calls [_performSave].
class AddEditEmployeeScreen extends StatefulWidget {
  final Employee? employee;
  final UserRole? fixedRole;

  const AddEditEmployeeScreen({super.key, this.employee, this.fixedRole});

  bool get isEditMode => employee != null;

  @override
  State<AddEditEmployeeScreen> createState() => _AddEditEmployeeScreenState();
}

class _AddEditEmployeeScreenState extends State<AddEditEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  TextEditingController? _fixedRoleController;

  UserRole? _role;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    _nameController = TextEditingController(text: employee?.name ?? '');
    _codeController = TextEditingController(text: employee?.employeeCode ?? '');
    _phoneController = TextEditingController(text: employee?.phoneLocal ?? '');
    _emailController = TextEditingController(text: employee?.email ?? '');
    _role = employee?.role ?? widget.fixedRole;
    if (widget.fixedRole != null) {
      _fixedRoleController =
          TextEditingController(text: widget.fixedRole!.displayLabel);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _fixedRoleController?.dispose();
    super.dispose();
  }

  String get _screenTitle {
    final roleLabel = widget.fixedRole?.displayLabel;
    if (widget.isEditMode) {
      return roleLabel != null ? 'Edit $roleLabel' : AppStrings.editEmployeeTitle;
    }
    return roleLabel != null ? 'Add $roleLabel' : AppStrings.addEmployeeTitle;
  }

  /// Roles the current user is allowed to hand out: Captains can add
  /// Project Controllers, Team Leaders and Employees; Project Controllers
  /// only the latter two (mirrors the wireframe, where "Add Project
  /// Controler" exists solely on the Captain's screen). Nobody creates
  /// Captains from the app. In edit mode the employee's own current role is
  /// kept in the list even when the editor couldn't normally assign it, so
  /// simply saving other fields never silently demotes anyone.
  List<UserRole> _assignableRoles(UserRole? currentUserRole) {
    final roles = currentUserRole == UserRole.captain
        ? [UserRole.projectManager, UserRole.teamLeader, UserRole.employee]
        : [UserRole.teamLeader, UserRole.employee];
    final existingRole = widget.employee?.role;
    if (existingRole != null && !roles.contains(existingRole)) {
      roles.insert(0, existingRole);
    }
    return roles;
  }

  /// Actually persists the form via [EmployeeViewModel] - only called from
  /// [ReviewEmployeeScreen] after the user confirms the "this will be saved
  /// permanently" dialog, never directly from this form.
  Future<ApiResult> _performSave() {
    final viewModel = context.read<EmployeeViewModel>();

    return widget.isEditMode
        ? viewModel.updateEmployee(
            widget.employee!.id,
            UpdateEmployeeRequest(
              name: _nameController.text.trim(),
              phone: _phoneController.text.trim(),
              email: _emailController.text.trim(),
              role: _role!.backendValue,
            ),
          )
        : viewModel.createEmployee(
            CreateEmployeeRequest(
              employeeCode: _codeController.text.trim(),
              name: _nameController.text.trim(),
              phone: _phoneController.text.trim(),
              email: _emailController.text.trim(),
              role: _role!.backendValue,
            ),
          );
  }

  Future<void> _goToReview() async {
    final roleError = _role == null ? 'Role is required' : null;
    final isFormValid = _formKey.currentState?.validate() ?? false;

    if (!isFormValid || roleError != null) {
      if (roleError != null) {
        SnackbarUtil.showError(context, roleError);
      }
      return;
    }

    if (!context.canPushRoute) return;

    final message = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewEmployeeScreen(
          isEditMode: widget.isEditMode,
          name: _nameController.text.trim(),
          role: _role!,
          employeeCode: _codeController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          onConfirmSave: _performSave,
        ),
      ),
    );

    // The review screen pops with the backend's success message once the
    // save actually succeeded; `null` means "Edit" was tapped (or it was
    // backgrounded), so this form stays open with its values untouched.
    // Pass the message all the way up: the list screen awaits this route
    // (see EmployeeListScreen._openAdd/_openEdit) and shows it there, after
    // every pop, so the app-wide SnackbarDismissingObserver can't wipe it.
    if (message != null && mounted) {
      Navigator.pop(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EmployeeViewModel>();
    final currentUserRole = context.watch<AuthViewModel>().role;

    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle),
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
                AppTextField(
                  controller: _nameController,
                  label: AppStrings.employeeFieldName,
                  icon: Icons.person_outline,
                  readOnly: widget.isEditMode,
                  validator: (value) => Validators.requiredField(
                    value,
                    AppStrings.employeeFieldName,
                  ),
                ),
                const SizedBox(height: AppDimensions.cardSpacing),
                if (widget.fixedRole != null)
                  AppTextField(
                    controller: _fixedRoleController!,
                    label: AppStrings.employeeFieldRole,
                    icon: Icons.badge_outlined,
                    readOnly: true,
                  )
                else
                  AppDropdown<UserRole>(
                    label: AppStrings.employeeFieldRole,
                    icon: Icons.badge_outlined,
                    value: _role,
                    items: _assignableRoles(currentUserRole),
                    itemLabel: (role) => role.displayLabel,
                    onChanged: (role) => setState(() => _role = role),
                    validator: (_) => _role == null ? 'Role is required' : null,
                  ),
                const SizedBox(height: AppDimensions.cardSpacing),
                AppTextField(
                  controller: _codeController,
                  label: AppStrings.employeeFieldCode,
                  icon: Icons.tag,
                  readOnly: widget.isEditMode,
                  validator: Validators.employeeCode,
                ),
                const SizedBox(height: AppDimensions.cardSpacing),
                AppTextField(
                  controller: _phoneController,
                  label: AppStrings.employeeFieldPhone,
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: Validators.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                ),
                const SizedBox(height: AppDimensions.cardSpacing),
                AppTextField(
                  controller: _emailController,
                  label: AppStrings.employeeFieldEmail,
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                ),
                if (!widget.isEditMode) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          AppStrings.addEmployeeWelcomeNote,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppDimensions.sectionSpacing),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: AppStrings.employeeCancelButton,
                        outlined: true,
                        onPressed: viewModel.isSaving
                            ? null
                            : () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.cardSpacing),
                    Expanded(
                      child: AppButton(
                        text: AppStrings.employeeNextButton,
                        isLoading: viewModel.isSaving,
                        onPressed: viewModel.isSaving ? null : _goToReview,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
