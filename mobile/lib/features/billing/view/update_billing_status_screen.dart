import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/billing_stage.dart';
import '../../../shared/enums/billing_status.dart';
import '../../../shared/enums/spoc_name.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_dropdown.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../model/billing_entry.dart';
import '../model/update_billing_status_request.dart';
import '../viewmodel/billing_view_model.dart';

/// Update Billing Status form (Captain / Project Controller only) - SPOC
/// and Billing Status are both fixed dropdowns (see [SpocName] /
/// [BillingStatus]); the Team Lead name is read-only, fetched from the
/// database. Pops with the resulting [BillingStage.apiValue] on success so
/// [BillingListScreen] can switch straight to the matching Pending/
/// Completed tab - selecting any status other than "Full payment received"
/// lands on Pending, selecting it lands directly on Completed.
class UpdateBillingStatusScreen extends StatefulWidget {
  final BillingEntry entry;

  const UpdateBillingStatusScreen({super.key, required this.entry});

  @override
  State<UpdateBillingStatusScreen> createState() =>
      _UpdateBillingStatusScreenState();
}

class _UpdateBillingStatusScreenState
    extends State<UpdateBillingStatusScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _remarksController;
  SpocName? _spoc;
  BillingStatus? _status;

  @override
  void initState() {
    super.initState();
    _spoc = SpocNameX.fromApiValue(widget.entry.spocName);
    _remarksController = TextEditingController(text: widget.entry.remarks ?? '');
    // Only pre-fill a status the project actually has - never default to a
    // dropdown value the user hasn't explicitly chosen and saved.
    _status = widget.entry.status != null
        ? BillingStatusX.fromApiValue(widget.entry.status)
        : null;
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (context.read<BillingViewModel>().isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final spoc = _spoc!;
    final status = _status!;

    final request = UpdateBillingStatusRequest(
      spocName: spoc.apiValue,
      status: status.apiValue,
      remarks: _remarksController.text.trim(),
    );

    final result = await context
        .read<BillingViewModel>()
        .updateBillingStatus(widget.entry.moduleId, request);
    if (!mounted) return;

    if (result.success) {
      final updated = result.data as BillingEntry?;
      final message = updated?.reversionPending == true
          ? AppStrings.submitChangeRequestSuccess
          : AppStrings.billingUpdateSuccess;
      // Passed through the pop result rather than shown here - see the
      // identical note on EditModuleScreen._submit: popping right after
      // queuing a snackbar clears it before it can render, since
      // SnackbarDismissingObserver wipes the messenger on every route
      // change. The caller shows it once back on a settled screen instead.
      Navigator.pop(context, (stage: updated?.stage, message: message));
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<BillingViewModel>();
    final canEdit = context.watch<AuthViewModel>().role == UserRole.projectManager &&
        widget.entry.editable;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.updateBillingTitle),
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
                Text(
                  widget.entry.moduleName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.entry.projectName,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text('ID: ${widget.entry.projectCode}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.badge_outlined,
                        size: 16, color: AppColors.textSecondaryFor(context)),
                    const SizedBox(width: 6),
                    Text(
                      '${AppStrings.billingFieldTeamLead}: '
                      '${widget.entry.teamLeadName ?? AppStrings.billingTeamLeadNotSet}',
                      style: TextStyle(color: AppColors.textSecondaryFor(context)),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.sectionSpacing),
                IgnorePointer(
                  ignoring: !canEdit,
                  child: Opacity(
                    opacity: canEdit ? 1 : 0.6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppDropdown<SpocName>(
                          label: AppStrings.billingFieldSpocName,
                          icon: Icons.person_outline,
                          value: _spoc,
                          items: SpocName.values,
                          itemLabel: (spoc) => spoc.label,
                          onChanged: (value) => setState(() => _spoc = value),
                          validator: (value) =>
                              value == null ? 'SPOC is required' : null,
                          showDropdownIcon: canEdit,
                        ),
                        const SizedBox(height: AppDimensions.cardSpacing),
                        AppDropdown<BillingStatus>(
                          label: AppStrings.billingFieldStatus,
                          icon: Icons.flag_outlined,
                          value: _status,
                          items: BillingStatus.values,
                          itemLabel: (status) => status.label,
                          onChanged: (value) => setState(() => _status = value),
                          validator: (value) =>
                              value == null ? 'Status is required' : null,
                          showDropdownIcon: canEdit,
                        ),
                        const SizedBox(height: AppDimensions.cardSpacing),
                        AppTextField(
                          controller: _remarksController,
                          label: AppStrings.billingFieldRemarks,
                          icon: Icons.notes_outlined,
                          hintText: AppStrings.billingRemarksHint,
                          maxLines: 4,
                        ),
                      ],
                    ),
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(height: AppDimensions.sectionSpacing),
                  AppButton(
                    text: AppStrings.updateBillingButton,
                    isLoading: viewModel.isSaving,
                    onPressed: viewModel.isSaving ? null : _submit,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
