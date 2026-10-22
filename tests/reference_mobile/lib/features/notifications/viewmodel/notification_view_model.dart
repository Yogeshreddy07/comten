import 'package:flutter/material.dart';

import '../model/notification_item.dart';
import '../repository/notification_repository.dart';

enum NotificationLoadState { initial, loading, success, error }

/// Owns Notifications module state for every role - the list, the unread
/// count (for the dashboard bell badge), and marking items read. Provided
/// app-wide (see main.dart) so the bell badge and the Notifications screen
/// stay in sync.
class NotificationViewModel extends ChangeNotifier {
  final NotificationRepository _repository;

  NotificationViewModel({required NotificationRepository repository})
      : _repository = repository;

  NotificationLoadState _loadState = NotificationLoadState.initial;
  List<NotificationItem> _notifications = [];
  String? _errorMessage;
  int _unreadCount = 0;

  NotificationLoadState get loadState => _loadState;
  List<NotificationItem> get notifications => _notifications;
  String? get errorMessage => _errorMessage;
  int get unreadCount => _unreadCount;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = NotificationLoadState.initial;
    _notifications = [];
    _errorMessage = null;
    _unreadCount = 0;
    notifyListeners();
  }

  Future<void> fetchNotifications() async {
    _loadState = NotificationLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getNotifications();

    if (result.success) {
      _notifications = (result.data as List<NotificationItem>?) ?? [];
      _loadState = NotificationLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = NotificationLoadState.error;
    }

    notifyListeners();
  }

  /// Refreshes just the unread badge count - cheap enough to call whenever
  /// the dashboard is shown, without loading the full list.
  Future<void> fetchUnreadCount() async {
    final result = await _repository.getUnreadCount();
    if (result.success) {
      _unreadCount = (result.data as int?) ?? 0;
      notifyListeners();
    }
  }

  Future<void> markAsRead(int id) async {
    NotificationItem? target;
    for (final n in _notifications) {
      if (n.id == id) {
        target = n;
        break;
      }
    }
    if (target == null || target.isRead) return;

    final result = await _repository.markAsRead(id);
    if (result.success) {
      _applyUpdate(result.data as NotificationItem?, id);
      if (_unreadCount > 0) _unreadCount--;
      notifyListeners();
    }
  }

  void _applyUpdate(NotificationItem? updated, int id) {
    if (updated == null) return;
    _notifications = _notifications.map((n) => n.id == id ? updated : n).toList();
  }
}
