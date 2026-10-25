import 'package:flutter/material.dart';

import '../../auth/model/api_result.dart';
import '../model/create_work_log_request.dart';
import '../model/work_log.dart';
import '../model/work_log_reminder.dart';
import '../repository/work_log_repository.dart';

enum WorkLogLoadState { initial, loading, success, error }

/// Owns "my timesheets" state for the Employee role - listing own
/// submissions and submitting new ones. The approval queue (Team Leader) is
/// a separate concern - see [WorkLogApprovalViewModel] - since the two
/// roles never share a screen.
class WorkLogViewModel extends ChangeNotifier {
  final WorkLogRepository _repository;

  WorkLogViewModel({required WorkLogRepository repository})
      : _repository = repository;

  // ---- List (GET /work-logs/my) ----
  WorkLogLoadState _loadState = WorkLogLoadState.initial;
  List<WorkLog> _workLogs = [];
  String? _errorMessage;
  int _revision = 0;
  int _session = 0;

  void _sort() {
    _workLogs.sort((a, b) {
      final byDate = b.workDate.compareTo(a.workDate);
      if (byDate != 0) return byDate;
      return (b.createdAt ?? b.workDate).compareTo(a.createdAt ?? a.workDate);
    });
  }

  WorkLogLoadState get loadState => _loadState;
  List<WorkLog> get workLogs => _workLogs;
  String? get errorMessage => _errorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _revision++;
    _session++;
    _loadState = WorkLogLoadState.initial;
    _workLogs = [];
    _errorMessage = null;
    _pendingReminderDayLabel = null;
    _isSubmitting = false;
    notifyListeners();
  }

  Future<void> fetchMyWorkLogs({int? moduleId, String? status}) async {
    final revision = ++_revision;
    if (_loadState != WorkLogLoadState.success) {
      _loadState = WorkLogLoadState.loading;
    }
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getMyWorkLogs(
      moduleId: moduleId,
      status: status,
    );
    if (revision != _revision) return;

    if (result.success) {
      _workLogs = List<WorkLog>.of((result.data as List<WorkLog>?) ?? const []);
      _sort();
      _loadState = WorkLogLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = WorkLogLoadState.error;
    }

    notifyListeners();
  }

  // ---- Missed Previous Day popup (GET /work-logs/reminder) ----
  String? _pendingReminderDayLabel;
  String? get pendingReminderDayLabel => _pendingReminderDayLabel;

  /// Fetched fresh every time [TimesheetListScreen] opens - never cached
  /// across calls, so the popup keeps appearing until the missing day's
  /// entry is actually completed.
  Future<void> fetchPendingReminder() async {
    final result = await _repository.getPendingReminder();
    if (result.success) {
      final reminder = result.data as WorkLogReminder?;
      _pendingReminderDayLabel = reminder?.missingDayLabel;
    } else {
      _pendingReminderDayLabel = null;
    }
    notifyListeners();
  }

  // ---- Submit (POST /work-logs) ----
  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  Future<ApiResult> submitWorkLog(CreateWorkLogRequest request) async {
    if (_isSubmitting) {
      return ApiResult(success: false, message: 'Timesheet submission is already in progress.');
    }
    final session = _session;
    _isSubmitting = true;
    notifyListeners();

    final result = await _repository.submitWorkLog(request);
    if (session != _session) return result;

    if (result.success) {
      _revision++;
      _loadState = WorkLogLoadState.success;
      _errorMessage = null;
      final created = result.data as WorkLog?;
      // A resubmit within the backend's duplicate window (see
      // `WorkLogServiceImpl#submitWorkLog`) returns the SAME existing entry
      // rather than a new one - only prepend it if it isn't already in the
      // list, so a double-click can't visually duplicate the row even
      // though the database itself only ever has the one.
      if (created != null && !_workLogs.any((w) => w.id == created.id)) {
        _workLogs = [created, ..._workLogs];
        _sort();
      }
    }

    _isSubmitting = false;
    notifyListeners();
    return result;
  }
}
