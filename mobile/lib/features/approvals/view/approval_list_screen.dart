import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/approval_status.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../billing/view/billing_approval_details_screen.dart';
import '../../billing/viewmodel/billing_approval_view_model.dart';
import '../../billing/widgets/billing_approval_card.dart';
import '../model/approval_queue_item.dart';
import '../viewmodel/approval_view_model.dart';
import '../widgets/approval_card.dart';
import '../widgets/project_deactivation_card.dart';
import 'approval_details_screen.dart';
import 'project_deactivation_details_screen.dart';

/// Approval module - Captain-only queue combining every kind of request
/// that needs a Captain's decision: Project Controller requests to change a
/// project's End Date/Estimated Hours ([ApprovalViewModel], see the
/// backend's `@PreAuthorize` on `/api/project-change-requests/**`),
/// requests to revert a completed billing project back to Pending
/// ([BillingApprovalViewModel], `/api/billing-status-change-requests/**`),
/// and requests to deactivate a project already in Billing Management
/// ([ApprovalViewModel], `/api/project-deactivation-requests/**`). They are
/// decided through separate backend endpoints/tables but are shown together
/// here so the Captain has one place to review everything.
class ApprovalListScreen extends StatefulWidget {
  const ApprovalListScreen({super.key});

  @override
  State<ApprovalListScreen> createState() => _ApprovalListScreenState();
}

class _ApprovalListScreenState extends State<ApprovalListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final approvalViewModel = context.read<ApprovalViewModel>();
      if (approvalViewModel.loadState == ApprovalLoadState.initial) {
        approvalViewModel.fetchChangeRequests();
      }
      final billingApprovalViewModel = context.read<BillingApprovalViewModel>();
      if (billingApprovalViewModel.loadState == BillingApprovalLoadState.initial) {
        billingApprovalViewModel.fetchChangeRequests();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh(BuildContext context) {
    context.read<ApprovalViewModel>().fetchChangeRequests();
    context.read<BillingApprovalViewModel>().fetchChangeRequests();
  }

  Future<void> _openDetails(BuildContext context, ApprovalQueueItem item) async {
    if (!context.canPushRoute) return;
    final result = await Navigator.push<({String message, bool isError})>(
      context,
      MaterialPageRoute(
        builder: (_) => switch (item.type) {
          ApprovalQueueItemType.projectChange =>
            ApprovalDetailsScreen(request: item.projectChangeRequest!),
          ApprovalQueueItemType.billingReversion => BillingApprovalDetailsScreen(
              request: item.billingStatusChangeRequest!,
            ),
          ApprovalQueueItemType.projectDeactivation =>
            ProjectDeactivationDetailsScreen(
              request: item.projectDeactivationRequest!,
            ),
        },
      ),
    );
    if (!context.mounted) return;
    _refresh(context);
    if (result != null) {
      if (result.isError) {
        SnackbarUtil.showError(context, result.message);
      } else {
        SnackbarUtil.showSuccess(context, result.message);
      }
    }
  }

  List<ApprovalQueueItem> _mergedItems(
    ApprovalViewModel approvalViewModel,
    BillingApprovalViewModel billingApprovalViewModel,
  ) {
    final items = <ApprovalQueueItem>[
      ...approvalViewModel.requests.map(ApprovalQueueItem.projectChange),
      ...billingApprovalViewModel.requests
          .map(ApprovalQueueItem.billingReversion),
      ...approvalViewModel.deactivationRequests
          .map(ApprovalQueueItem.projectDeactivation),
    ];
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  List<ApprovalQueueItem> _filter(List<ApprovalQueueItem> items, int tabIndex) {
    final status = switch (tabIndex) {
      1 => ApprovalStatus.approved,
      2 => ApprovalStatus.rejected,
      _ => ApprovalStatus.pending,
    };
    return items.where((item) => item.effectiveStatus == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    final approvalViewModel = context.watch<ApprovalViewModel>();
    final billingApprovalViewModel = context.watch<BillingApprovalViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.approvalListTitle),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: AppStrings.approvalTabPending),
            Tab(text: AppStrings.approvalTabApproved),
            Tab(text: AppStrings.approvalTabRejected),
          ],
        ),
      ),
      body: SafeArea(
        child: _buildBody(context, approvalViewModel, billingApprovalViewModel),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ApprovalViewModel approvalViewModel,
    BillingApprovalViewModel billingApprovalViewModel,
  ) {
    final loading = approvalViewModel.loadState == ApprovalLoadState.initial ||
        approvalViewModel.loadState == ApprovalLoadState.loading ||
        billingApprovalViewModel.loadState == BillingApprovalLoadState.initial ||
        billingApprovalViewModel.loadState == BillingApprovalLoadState.loading;
    if (loading) {
      return const AppLoader(message: AppStrings.approvalLoading);
    }

    final error = approvalViewModel.loadState == ApprovalLoadState.error
        ? approvalViewModel.errorMessage
        : billingApprovalViewModel.loadState == BillingApprovalLoadState.error
            ? billingApprovalViewModel.errorMessage
            : null;
    if (error != null) {
      return AppEmptyView(
        icon: Icons.cloud_off_outlined,
        title: AppStrings.approvalLoadErrorTitle,
        message: error,
        actionLabel: 'Retry',
        onAction: () => _refresh(context),
      );
    }

    final merged = _mergedItems(approvalViewModel, billingApprovalViewModel);
    return TabBarView(
      controller: _tabController,
      children: [
        for (var tabIndex = 0; tabIndex < 3; tabIndex++)
          _buildList(context, merged, tabIndex),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    List<ApprovalQueueItem> items,
    int tabIndex,
  ) {
    final filtered = _filter(items, tabIndex);

    if (filtered.isEmpty) {
      return const AppEmptyView(
        icon: Icons.fact_check_outlined,
        title: AppStrings.approvalEmptyTitle,
        message: AppStrings.approvalEmptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _refresh(context),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = filtered[index];
          return switch (item.type) {
            ApprovalQueueItemType.projectChange => ApprovalCard(
                request: item.projectChangeRequest!,
                onTap: () => _openDetails(context, item),
              ),
            ApprovalQueueItemType.billingReversion => BillingApprovalCard(
                request: item.billingStatusChangeRequest!,
                onTap: () => _openDetails(context, item),
              ),
            ApprovalQueueItemType.projectDeactivation => ProjectDeactivationCard(
                request: item.projectDeactivationRequest!,
                onTap: () => _openDetails(context, item),
              ),
          };
        },
      ),
    );
  }
}
