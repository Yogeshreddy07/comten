import 'package:flutter/material.dart';

import '../../auth/model/api_result.dart';
import '../model/activity.dart';
import '../repository/activity_repository.dart';

enum ActivityLoadState { initial, loading, success, error }

/// Owns the Activities master-list state - shared by the Project
/// Controller's Activities screen and the Project create/edit Billable/
/// Non-Billable pickers (all read from the same [activities] list).
class ActivityViewModel extends ChangeNotifier {
  final ActivityRepository _repository;

  ActivityViewModel({required ActivityRepository repository})
      : _repository = repository;

  ActivityLoadState _loadState = ActivityLoadState.initial;
  List<Activity> _activities = [];
  String? _errorMessage;

  ActivityLoadState get loadState => _loadState;
  List<Activity> get activities => _activities;
  String? get errorMessage => _errorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = ActivityLoadState.initial;
    _activities = [];
    _errorMessage = null;
    _isSaving = false;
    notifyListeners();
  }

  Future<void> fetchActivities() async {
    _loadState = ActivityLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getActivities();

    if (result.success) {
      _activities = (result.data as List<Activity>?) ?? [];
      _loadState = ActivityLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = ActivityLoadState.error;
    }

    notifyListeners();
  }

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  Future<ApiResult> createActivity(String name) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.createActivity(name);

    if (result.success) {
      final created = result.data as Activity?;
      if (created != null) {
        _activities = [..._activities, created]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }

  Future<ApiResult> deleteActivity(int id) async {
    final result = await _repository.deleteActivity(id);

    if (result.success) {
      _activities = _activities.where((activity) => activity.id != id).toList();
      notifyListeners();
    }

    return result;
  }
}
