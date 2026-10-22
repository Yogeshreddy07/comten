import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../modules/view/edit_module_screen.dart';
import '../../projects/widgets/review_summary_card.dart';
import '../model/notification_item.dart';

/// Read-only detail of a Reason for Delay request, reached by a Project
/// Controller tapping a `DELAY_REQUESTED` notification. Purely informational
/// (Team Lead -> Project Controller) - there is no approve/reject action,
/// just a Continue shortcut straight into editing the module in question
/// when the notification has one (older, pre-modules notifications may not).
class DelayRequestDetailsScreen extends StatelessWidget {
  final NotificationItem notification;

  const DelayRequestDetailsScreen({super.key, required this.notification});

  Future<void> _continue(BuildContext context) async {
    if (!context.canPushRoute) return;
    final result = await Navigator.push<({String message, bool isError})>(
      context,
      MaterialPageRoute(
        builder: (_) => EditModuleScreen(moduleId: notification.moduleId!),
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
                    notification.projectName ?? '-',
                  ),
                  ReviewDetailRow(
                    AppStrings.notificationFieldSubmittedBy,
                    notification.senderName ?? '-',
                  ),
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
                    Text(notification.reason ?? '-'),
                  ],
                ),
              ),
              if (notification.moduleId != null) ...[
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
