import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/billing_stage.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../model/billing_entry.dart';
import '../viewmodel/billing_view_model.dart';
import '../widgets/billing_card.dart';
import 'update_billing_status_screen.dart';

/// Billing Management - Captain / Project Controller landing screen.
/// Mirrors the wireframe's three-step flow as three tabs over the same
/// project list: Not Set (no billing record yet - pick one to set it up),
/// Pending, and Completed - updating a project's billing status switches
/// straight to whichever of the latter two tabs now matches it.
class BillingListScreen extends StatefulWidget {
  const BillingListScreen({super.key});

  @override
  State<BillingListScreen> createState() => _BillingListScreenState();
}

class _BillingListScreenState extends State<BillingListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Always refetch on entry (not just the first time) - BillingViewModel is
    // provided app-wide and would otherwise keep showing whatever was loaded
    // the last time this screen was open, hiding modules a Team Lead has
    // since moved into the Billing work stage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BillingViewModel>().fetchBillingList();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openUpdate(BuildContext context, BillingEntry entry) async {
    if (!context.canPushRoute) return;
    final result = await Navigator.push<({String? stage, String message})>(
      context,
      MaterialPageRoute(
        builder: (_) => UpdateBillingStatusScreen(entry: entry),
      ),
    );
    if (!context.mounted || result == null) return;

    SnackbarUtil.showSuccess(context, result.message);

    if (result.stage == null) return;
    // Land on the tab matching the new stage.
    final stage = BillingStageX.fromApiValue(result.stage!);
    _tabController.animateTo(switch (stage) {
      BillingStage.toBeBilled => 0,
      BillingStage.pending => 1,
      BillingStage.completed => 2,
    });
  }

  List<BillingEntry> _filter(List<BillingEntry> entries, int tabIndex) {
    switch (tabIndex) {
      case 1:
        return entries
            .where((e) => e.effectiveStage == BillingStage.pending)
            .toList();
      case 2:
        return entries
            .where((e) => e.effectiveStage == BillingStage.completed)
            .toList();
      default:
        // Sent to billing but still at the default INVOICE_YET_TO_BE_RAISED
        // status - the Project Controller's to-do list for moving it along.
        return entries
            .where((e) => e.effectiveStage == BillingStage.toBeBilled)
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<BillingViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.billingListTitle),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: AppStrings.billingTabNotSet),
            Tab(text: AppStrings.billingTabPending),
            Tab(text: AppStrings.billingTabCompleted),
          ],
        ),
      ),
      body: SafeArea(
        child: _buildBody(context, viewModel),
      ),
    );
  }

  Widget _buildBody(BuildContext context, BillingViewModel viewModel) {
    switch (viewModel.loadState) {
      case BillingLoadState.initial:
      case BillingLoadState.loading:
        return const AppLoader(message: AppStrings.billingLoading);

      case BillingLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.billingLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchBillingList(),
        );

      case BillingLoadState.success:
        return TabBarView(
          controller: _tabController,
          children: [
            for (var tabIndex = 0; tabIndex < 3; tabIndex++)
              _buildList(context, viewModel, tabIndex),
          ],
        );
    }
  }

  Widget _buildList(
    BuildContext context,
    BillingViewModel viewModel,
    int tabIndex,
  ) {
    final filtered = _filter(viewModel.entries, tabIndex);

    if (filtered.isEmpty) {
      return const AppEmptyView(
        icon: Icons.receipt_long_outlined,
        title: AppStrings.billingEmptyTitle,
        message: AppStrings.billingEmptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: viewModel.fetchBillingList,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final entry = filtered[index];
          return BillingCard(
            entry: entry,
            onTap: () => _openUpdate(context, entry),
          );
        },
      ),
    );
  }
}
