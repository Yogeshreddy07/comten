import 'package:flutter/material.dart';
import '../model/employee.dart';
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
class ReviewEmployeeScreen extends StatelessWidget {
  final bool isEditMode;
  final String name;
  final UserRole role;
  final String employeeCode;
  final String phone;
  final String email;
  final Future<ApiResult> Function() onConfirmSave;

  const ReviewEmployeeScreen({
    super.key,
    required this.isEditMode,
    required this.name,
    required this.role,
    required this.employeeCode,
    required this.phone,
    required this.email,
    required this.onConfirmSave,
  });

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
    // Resolve the messenger for the failure path now: everything after
    // dialog-confirming Save runs after an await, when this screen's
    // context may be stale.
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _showConfirmDialog(context);
    if (!confirmed || !context.mounted) return;

    final result = await onConfirmSave();
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
      SnackbarUtil.showErrorOn(messenger, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EmployeeViewModel>();
    final roleLabel = role.displayLabel;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditMode
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
                  ReviewDetailRow(AppStrings.employeeFieldName, name),
                  ReviewDetailRow(AppStrings.employeeFieldRole, roleLabel),
                  ReviewDetailRow(AppStrings.employeeFieldCode, employeeCode),
                  ReviewDetailRow(AppStrings.employeeFieldPhone, phone),
                  ReviewDetailRow(AppStrings.employeeFieldEmail, email),
                ],
              ),
              const SizedBox(height: AppDimensions.cardSpacing),
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
                      onPressed: viewModel.isSaving
                          ? null
                          : () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.cardSpacing),
                  Expanded(
                    child: AppButton(
                      text: AppStrings.reviewEmployeeConfirmButton,
                      isLoading: viewModel.isSaving,
                      onPressed: viewModel.isSaving
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
