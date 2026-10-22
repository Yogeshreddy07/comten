import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../model/notification_item.dart';
import '../utils/notification_navigator.dart';
import '../viewmodel/notification_view_model.dart';
import '../widgets/notification_card.dart';

/// Shown in place of the dashboard whenever the user has unread
/// notifications at app entry (see `RoleDashboardNavigator.navigate`) -
/// every unread item must be viewed or dismissed before [dashboard]
/// replaces this screen. By the time this is pushed, `fetchNotifications()`
/// has already completed, so the initial state renders instantly with no
/// extra loading flash.
class UnreadNotificationsGateScreen extends StatefulWidget {
  final Widget dashboard;

  const UnreadNotificationsGateScreen({super.key, required this.dashboard});

  @override
  State<UnreadNotificationsGateScreen> createState() =>
      _UnreadNotificationsGateScreenState();
}

class _UnreadNotificationsGateScreenState
    extends State<UnreadNotificationsGateScreen> {
  bool _navigated = false;

  /// Auto-advances once every notification has been read - but only while
  /// this screen is actually the visible route. Without the `isCurrent`
  /// guard, marking the last item read while a detail screen is pushed on
  /// top (covering this screen, not popping it) still triggers a rebuild
  /// here via `context.watch`, which would silently `pushReplacement` this
  /// screen out from under the visible detail screen - surfacing later as
  /// an unexpected jump back to the dashboard once the user backs out.
  void _maybeAdvance(
    NotificationViewModel viewModel,
    List<NotificationItem> unread,
  ) {
    if (_navigated) return;
    if (viewModel.loadState != NotificationLoadState.success) return;
    if (unread.isNotEmpty) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;

    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => widget.dashboard),
      );
    });
  }

  /// Manual escape hatch - any notification the user hasn't tapped stays
  /// unread (no `markAsRead` call here), so it reappears on this same
  /// screen next time there are unread notifications to show.
  void _continue() {
    if (_navigated) return;
    _navigated = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => widget.dashboard),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<NotificationViewModel>();
    final unread = viewModel.notifications.where((n) => !n.isRead).toList();

    _maybeAdvance(viewModel, unread);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.notificationGateTitle),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(child: _buildBody(context, viewModel, unread)),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NotificationViewModel viewModel,
    List<NotificationItem> unread,
  ) {
    switch (viewModel.loadState) {
      case NotificationLoadState.initial:
      case NotificationLoadState.loading:
        return const AppLoader(message: AppStrings.notificationListLoading);

      case NotificationLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.notificationGateLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchNotifications(),
        );

      case NotificationLoadState.success:
        if (unread.isEmpty) {
          // About to auto-advance to the dashboard - nothing to render.
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(AppStrings.notificationGateMessage),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: unread.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final notification = unread[index];
                  return NotificationCard(
                    notification: notification,
                    onTap: () => NotificationNavigator.openNotification(
                      context,
                      notification,
                      viewModel,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                0,
                AppDimensions.screenPadding,
                AppDimensions.screenPadding,
              ),
              child: AppButton(
                text: AppStrings.notificationGateContinueButton,
                onPressed: _continue,
              ),
            ),
          ],
        );
    }
  }
}
