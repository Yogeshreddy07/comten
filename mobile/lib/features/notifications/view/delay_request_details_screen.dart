import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../../modules/view/edit_module_screen.dart';
import '../../projects/widgets/review_summary_card.dart';
import '../model/delay_request.dart';
import '../model/notification_item.dart';

/// Detail of a Reason for Delay request, reached by tapping a
/// `DELAY_REQUESTED` notification (Captain / Project Controller) or its
/// `DELAY_APPROVED`/`DELAY_REJECTED` outcome (Team Lead). While the request
/// is `PENDING` a Captain or Project Controller can Approve/Reject it - until
/// then the Team Lead can't submit another delay for the same module. Also
/// keeps the Continue shortcut into editing the module for managers.
/// Older notifications have no [NotificationItem.delayRequestId]; those stay
/// read-only, showing just the notification's own reason.
class DelayRequestDetailsScreen extends StatefulWidget {
  final NotificationItem notification;

  const DelayRequestDetailsScreen({super.key, required this.notification});

  @override
  State<DelayRequestDetailsScreen> createState() =>
      _DelayRequestDetailsScreenState();
}

enum _PendingAction { approve, reject }

class _DelayRequestDetailsScreenState extends State<DelayRequestDetailsScreen> {
  final _repository = DependencyInjection.notificationRepository;
  final _reasonController = TextEditingController();
  String? _reasonError;
  _PendingAction? _pendingAction;

  DelayRequest? _request;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRequest();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadRequest() async {
    final id = widget.notification.delayRequestId;
    if (id == null) return;
    setState(() => _isLoading = true);
    final result = await _repository.getDelayRequest(id);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.success) _request = result.data as DelayRequest?;
    });
    if (!result.success) SnackbarUtil.showError(context, result.message);
  }

  Future<void> _decide(_PendingAction action) async {
    final request = _request;
    if (request == null) return;
    final reason = _reasonController.text.trim();
    if (action == _PendingAction.reject && reason.isEmpty) {
      setState(() => _reasonError = AppStrings.approvalReasonRequiredError);
      return;
    }

    setState(() => _pendingAction = action);
    final result = action == _PendingAction.approve
        ? await _repository.approveDelayRequest(request.id, reason)
        : await _repository.rejectDelayRequest(request.id, reason);
    if (!mounted) return;
    setState(() => _pendingAction = null);

    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);
      _reasonController.clear();
      await _loadRequest();
    } else {
      SnackbarUtil.showError(context, result.message);
      // Someone else may have decided it meanwhile - show the current state.
      await _loadRequest();
    }
  }

  Future<void> _continue(BuildContext context) async {
    if (!context.canPushRoute) return;
    final result = await Navigator.push<({String message, bool isError})>(
      context,
      MaterialPageRoute(
        builder: (_) => EditModuleScreen(moduleId: widget.notification.moduleId!),
      ),
    );
    if (!context.mounted || result == null) return;
    if (result.isError) {
      SnackbarUtil.showError(context, result.message);
    } else {
      SnackbarUtil.showSuccess(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;
    final request = _request;
    final role = context.watch<AuthViewModel>().role;
    final isManager =
        role == UserRole.captain || role == UserRole.projectManager;
    final status = request?.effectiveStatus;
    final canDecide = isManager && status == ApprovalStatus.pending;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.notificationDetailsTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                child: Text(
                  notification.title,
                  style: AppTextStyles.heading.copyWith(fontSize: 20),
                ),
              ),
              const SizedBox(height: 16),
              ReviewSummarySection(
                title: 'Request Details',
                rows: [
                  ReviewDetailRow(
                    AppStrings.notificationFieldProject,
                    request?.projectName ?? notification.projectName ?? '-',
                  ),
                  if ((request?.moduleName ?? notification.moduleName) != null)
                    ReviewDetailRow(
                      'Module',
                      request?.moduleName ?? notification.moduleName!,
                    ),
                  ReviewDetailRow(
                    AppStrings.notificationFieldSubmittedBy,
                    request?.requestedByName ?? notification.senderName ?? '-',
                  ),
                  if (status != null) ReviewDetailRow('Status', status.label),
                ],
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.notificationFieldReason,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(request?.reason ?? notification.reason ?? '-'),
                  ],
                ),
              ),
              if (_isLoading) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
              ],
              if (canDecide) ...[
                const SizedBox(height: 20),
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
                        onPressed: _pendingAction != null
                            ? null
                            : () => _decide(_PendingAction.reject),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        text: AppStrings.approvalApproveButton,
                        isLoading: _pendingAction == _PendingAction.approve,
                        onPressed: _pendingAction != null
                            ? null
                            : () => _decide(_PendingAction.approve),
                      ),
                    ),
                  ],
                ),
              ] else if (request != null && status != ApprovalStatus.pending) ...[
                const SizedBox(height: 16),
                ReviewSummarySection(
                  title: 'Decision',
                  rows: [
                    ReviewDetailRow('Status', status!.label),
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
              if (isManager && notification.moduleId != null) ...[
                const SizedBox(height: 20),
                AppButton(
                  text: AppStrings.notificationContinueButton,
                  onPressed: () => _continue(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
