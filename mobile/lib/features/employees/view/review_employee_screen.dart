import 'package:flutter/material.dart';
import '../model/employee.dart';
import '../model/employee_identity_validation.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_button.dart';
import '../../auth/model/api_result.dart';
import '../../projects/widgets/review_summary_card.dart';
import '../viewmodel/employee_view_model.dart';

/// Read-only confirmation step shown between the Add/Edit Employee form and
/// the actual save, per the "review before you commit" flow: form -> Review
/// (this screen) -> confirmation dialog -> save.
///
/// "Edit" just pops back to the still-alive [AddEditEmployeeScreen] (its
/// State, and therefore every controller value, is untouched underneath
/// this route) so the user lands back on the form pre-filled exactly as
/// they left it. "Confirm" opens a dialog warning that the save is
/// permanent; only tapping "Save" in that dialog actually calls
/// [onConfirmSave] and persists the record. On success this screen pops
/// with the backend's message string instead of showing it itself - the
/// list screen displays it once the whole add/edit flow has unwound.
class ReviewEmployeeScreen extends StatefulWidget {
  final bool isEditMode;
  final String name;
  final UserRole role;
  final String employeeCode;
  final String phone;
  final String email;
  final Future<ApiResult> Function() onConfirmSave;
  final Future<ApiResult> Function() onValidateIdentity;

  const ReviewEmployeeScreen({
    super.key,
    required this.isEditMode,
    required this.name,
    required this.role,
    required this.employeeCode,
    required this.phone,
    required this.email,
    required this.onConfirmSave,
    required this.onValidateIdentity,
  });

  @override
  State<ReviewEmployeeScreen> createState() => _ReviewEmployeeScreenState();
}

class _ReviewEmployeeScreenState extends State<ReviewEmployeeScreen> {
  bool _checkingIdentity = true;
  bool _confirming = false;
  Map<String, String> _identityErrors = {};
  String? _identityCheckError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _validateIdentity(); });
  }

  Future<bool> _validateIdentity() async {
    setState(() { _checkingIdentity = true; _identityCheckError = null; });
    ApiResult result;
    try {
      result = await widget.onValidateIdentity();
    } catch (_) {
      result = ApiResult(success: false, message: 'Unable to validate employee details. Please retry.');
    }
    if (!mounted) return false;
    final validation = result.data;
    setState(() {
      _checkingIdentity = false;
      if (result.success && validation is EmployeeIdentityValidation) {
        _identityErrors = validation.errors;
      } else {
        _identityCheckError = result.success ? 'Unable to validate employee details. Please retry.' : result.message;
      }
    });
    return _identityCheckError == null && _identityErrors.isEmpty;
  }

  Future<bool> _showConfirmDialog(BuildContext context) async {
    if (!context.canPushRoute) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(AppStrings.confirmSaveEmployeeTitle),
        content: const Text(AppStrings.confirmSaveEmployeeMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(AppStrings.confirmSaveEmployeeCancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(AppStrings.confirmSaveEmployeeSaveButton),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _handleConfirm(BuildContext context) async {
    if (_confirming || _checkingIdentity || _identityErrors.isNotEmpty || _identityCheckError != null) return;
    setState(() => _confirming = true);
    try {
      await _confirmAndSave(context);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _confirmAndSave(BuildContext context) async {
    // Resolve the messenger for the failure path now: everything after
    // dialog-confirming Save runs after an await, when this screen's
    // context may be stale.
    final messenger = ScaffoldMessenger.of(context);
    if (!await _validateIdentity() || !context.mounted) return;
    final confirmed = await _showConfirmDialog(context);
    if (!confirmed || !context.mounted) return;
    if (!await _validateIdentity() || !context.mounted) return;

    final result = await widget.onConfirmSave();
    if (!context.mounted) return;

    if (result.success) {
      final employee=result.data;
      if(employee is Employee && employee.temporaryPassword!=null) {
        await showDialog<void>(context:context,builder:(dialogContext)=>AlertDialog(
          title:const Text('Account created'),
          content:SelectableText('Employee code: ${employee.employeeCode}\nTemporary password: ${employee.temporaryPassword}\n\nShare these through your approved private channel.'),
          actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Done'))],
        ));
        if(!context.mounted) return;
      }
      // Don't show the message here: this screen pops immediately and the
      // app-wide SnackbarDismissingObserver (main.dart) clears any snackbar
      // on route change, so it would never be seen. Instead pop the success
      // message up through the form screen to the list screen, which shows
      // it only once every pop has settled.
      Navigator.pop(context, result.message);
    } else {
      await _validateIdentity();
      if (!context.mounted) return;
      SnackbarUtil.showErrorOn(messenger, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EmployeeViewModel>();
    final roleLabel = widget.role.displayLabel;
    final busy = viewModel.isSaving || _confirming || _checkingIdentity;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditMode
              ? AppStrings.reviewEditEmployeeTitle(roleLabel)
              : AppStrings.reviewAddEmployeeTitle(roleLabel),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReviewSummarySection(
                title: AppStrings.reviewEmployeeSectionTitle,
                rows: [
                  ReviewDetailRow(AppStrings.employeeFieldName, widget.name),
                  ReviewDetailRow(AppStrings.employeeFieldRole, roleLabel),
                  ReviewDetailRow(AppStrings.employeeFieldCode, widget.employeeCode),
                  ReviewDetailRow(AppStrings.employeeFieldPhone, widget.phone),
                  ReviewDetailRow(AppStrings.employeeFieldEmail, widget.email),
                ],
              ),
              const SizedBox(height: AppDimensions.cardSpacing),
              for (final error in _identityErrors.values)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))),
              if (_identityCheckError != null) ...[
                Text(_identityCheckError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                TextButton(onPressed: busy ? null : _validateIdentity, child: const Text('Retry validation')),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AppStrings.reviewEmployeeWarning,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.sectionSpacing),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: AppStrings.reviewEmployeeEditButton,
                      outlined: true,
                      onPressed: viewModel.isSaving || _confirming
                          ? null
                          : () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.cardSpacing),
                  Expanded(
                    child: AppButton(
                      text: AppStrings.reviewEmployeeConfirmButton,
                      isLoading: viewModel.isSaving || _checkingIdentity,
                      onPressed: busy || _identityErrors.isNotEmpty || _identityCheckError != null
                          ? null
                          : () => _handleConfirm(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
