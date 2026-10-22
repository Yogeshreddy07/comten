import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../model/notification_item.dart';
import '../utils/notification_navigator.dart';
import '../viewmodel/notification_view_model.dart';
import '../widgets/notification_card.dart';

/// Notifications - shared across every role (see `NotificationServiceImpl
/// #getNotifications`, scoped server-side to the current user/role).
/// Tapping a `DELAY_REQUESTED` notification opens the full Reason for
/// Delay detail (with Approve/Reject for a Project Controller); every
/// other notification just gets marked read in place.
/// [NotificationViewModel] is provided app-wide (see main.dart) so the
/// dashboard's unread bell badge stays in sync.
class NotificationListScreen extends StatefulWidget {
  const NotificationListScreen({super.key});

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationViewModel>().fetchNotifications();
    });
  }

  Future<void> _openNotification(
    BuildContext context,
    NotificationItem notification,
  ) {
    final viewModel = context.read<NotificationViewModel>();
    return NotificationNavigator.openNotification(context, notification, viewModel);
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<NotificationViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.notificationListTitle),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(context, viewModel)),
    );
  }

  Widget _buildBody(BuildContext context, NotificationViewModel viewModel) {
    switch (viewModel.loadState) {
      case NotificationLoadState.initial:
      case NotificationLoadState.loading:
        return const AppLoader(message: AppStrings.notificationListLoading);

      case NotificationLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.notificationListLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchNotifications(),
        );

      case NotificationLoadState.success:
        if (viewModel.notifications.isEmpty) {
          return const AppEmptyView(
            icon: Icons.notifications_none_outlined,
            title: AppStrings.notificationListEmptyTitle,
            message: AppStrings.notificationListEmptyMessage,
          );
        }

        return RefreshIndicator(
          onRefresh: viewModel.fetchNotifications,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: viewModel.notifications.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final notification = viewModel.notifications[index];
              return NotificationCard(
                notification: notification,
                onTap: () => _openNotification(context, notification),
              );
            },
          ),
        );
    }
  }
}
