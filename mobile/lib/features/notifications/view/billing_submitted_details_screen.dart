import 'package:flutter/material.dart';

import '../../../core/di/dependency_injection.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../billing/model/billing_entry.dart';
import '../../billing/view/update_billing_status_screen.dart';
import '../../projects/widgets/review_summary_card.dart';
import '../model/notification_item.dart';

/// Read-only detail of a `PROJECT_SUBMITTED_FOR_BILLING` notification,
/// reached by a Project Controller or Captain tapping it. Continue looks up
/// the matching [BillingEntry] (there is no single-module billing GET, only
/// the bulk list - see [BillingRepository.getBillingList]) and opens
/// [UpdateBillingStatusScreen] directly on it, skipping the Billing
/// Management listing entirely.
class BillingSubmittedDetailsScreen extends StatefulWidget {
  final NotificationItem notification;

  const BillingSubmittedDetailsScreen({super.key, required this.notification});

  @override
  State<BillingSubmittedDetailsScreen> createState() =>
      _BillingSubmittedDetailsScreenState();
}

class _BillingSubmittedDetailsScreenState
    extends State<BillingSubmittedDetailsScreen> {
  bool _loading = false;

  Future<void> _continue() async {
    setState(() => _loading = true);
    final result = await DependencyInjection.billingRepository.getBillingList();
    if (!mounted) return;
    setState(() => _loading = false);

    if (!result.success) {
      SnackbarUtil.showError(context, result.message);
      return;
    }

    final entries = (result.data as List<BillingEntry>?) ?? [];
    BillingEntry? found;
    for (final entry in entries) {
      if (entry.moduleId == widget.notification.moduleId) {
        found = entry;
        break;
      }
    }

    if (found == null) {
      SnackbarUtil.showError(context, AppStrings.notificationBillingEntryNotFound);
      return;
    }

    if (!mounted) return;
    final updateResult = await Navigator.push<({String? stage, String message})>(
      context,
      MaterialPageRoute(builder: (_) => UpdateBillingStatusScreen(entry: found!)),
    );
    if (!mounted || updateResult == null) return;
    SnackbarUtil.showSuccess(context, updateResult.message);
  }

  @override
  Widget build(BuildContext context) {
    final notification = widget.notification;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.notificationBillingSubmittedTitle),
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
                title: 'Details',
                rows: [
                  ReviewDetailRow(
                    AppStrings.notificationFieldProject,
                    notification.projectName ?? '-',
                  ),
                  ReviewDetailRow(
                    AppStrings.notificationFieldModule,
                    notification.moduleName ?? '-',
                  ),
                  ReviewDetailRow(
                    AppStrings.notificationFieldSubmittedBy,
                    notification.senderName ?? '-',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppCard(child: Text(notification.message)),
              if (notification.moduleId != null) ...[
                const SizedBox(height: 20),
                AppButton(
                  text: AppStrings.notificationContinueButton,
                  isLoading: _loading,
                  onPressed: _loading ? null : _continue,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
