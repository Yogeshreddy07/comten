import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../../projects/widgets/review_summary_card.dart';
import '../model/project_deactivation_request.dart';
import '../viewmodel/approval_view_model.dart';

/// Detail view of a single [ProjectDeactivationRequest] - mirrors
/// [ApprovalDetailsScreen]. A Captain sees a reason field plus
/// Approve/Reject while the request is `PENDING` (approve deactivates the
/// project and its billing entries read as Completed; reject leaves
/// everything unchanged); everyone else, or once decided, sees a read-only
/// summary including the decision reason.
class ProjectDeactivationDetailsScreen extends StatefulWidget {
  final ProjectDeactivationRequest request;

  const ProjectDeactivationDetailsScreen({super.key, required this.request});

  @override
  State<ProjectDeactivationDetailsScreen> createState() =>
      _ProjectDeactivationDetailsScreenState();
}

enum _PendingAction { approve, reject }

class _ProjectDeactivationDetailsScreenState
    extends State<ProjectDeactivationDetailsScreen> {
  late final TextEditingController _reasonController;
  String? _reasonError;
  _PendingAction? _pendingAction;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool _validateReason() {
    final reason = _reasonController.text.trim();
    setState(() {
      _reasonError = reason.isEmpty ? AppStrings.approvalReasonRequiredError : null;
    });
    return _reasonError == null;
  }

  Future<void> _approve() async {
    setState(() => _pendingAction = _PendingAction.approve);
    final viewModel = context.read<ApprovalViewModel>();
    final result = await viewModel.approveDeactivation(
      widget.request.id,
      _reasonController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (result.success) {
      Navigator.pop(context, (message: AppStrings.approvalApproveSuccess, isError: false));
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  Future<void> _reject() async {
    if (!_validateReason()) return;
    setState(() => _pendingAction = _PendingAction.reject);
    final viewModel = context.read<ApprovalViewModel>();
    final result = await viewModel.rejectDeactivation(
      widget.request.id,
      _reasonController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _pendingAction = null);
    if (result.success) {
      Navigator.pop(context, (message: AppStrings.approvalRejectSuccess, isError: false));
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final role = context.watch<AuthViewModel>().role;
    final viewModel = context.watch<ApprovalViewModel>();
    final canDecide = role == UserRole.captain &&
        request.effectiveStatus == ApprovalStatus.pending;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.approvalDetailsTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReviewSummarySection(
                title: request.projectName,
                rows: [
                  ReviewDetailRow('Project ID', request.projectCode),
                  ReviewDetailRow(
                    AppStrings.approvalFieldRequestedBy,
                    request.requestedByName,
                  ),
                  const ReviewDetailRow(
                    'Requested change',
                    'Deactivate this project (currently in Billing Management)',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const ReviewSummarySection(
                title: 'On approval',
                rows: [
                  ReviewDetailRow('Project status', 'Becomes Inactive'),
                  ReviewDetailRow('Billing Management', 'Moves to Completed'),
                ],
              ),
              const SizedBox(height: 16),
              if (canDecide) ...[
                AppTextField(
                  controller: _reasonController,
                  label: AppStrings.approvalFieldDecisionReason,
                  icon: Icons.notes_outlined,
                  hintText: AppStrings.approvalDecisionReasonHint,
                  maxLines: 4,
                  errorText: _reasonError,
                  onChanged: (_) {
                    if (_reasonError != null) setState(() => _reasonError = null);
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: AppStrings.approvalRejectButton,
                        outlined: true,
                        isLoading: _pendingAction == _PendingAction.reject,
                        onPressed: viewModel.isSaving ? null : _reject,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        text: AppStrings.approvalApproveButton,
                        isLoading: _pendingAction == _PendingAction.approve,
                        onPressed: viewModel.isSaving ? null : _approve,
                      ),
                    ),
                  ],
                ),
              ] else if (request.decisionReason != null ||
                  request.effectiveStatus != ApprovalStatus.pending) ...[
                ReviewSummarySection(
                  title: 'Decision',
                  rows: [
                    ReviewDetailRow('Status', request.effectiveStatus.label),
                    if (request.decidedByName != null)
                      ReviewDetailRow('Decided By', request.decidedByName!),
                    if (request.decisionReason != null)
                      ReviewDetailRow(
                        AppStrings.approvalFieldDecisionReason,
                        request.decisionReason!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
