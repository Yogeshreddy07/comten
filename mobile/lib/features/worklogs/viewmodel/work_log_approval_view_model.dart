import 'package:flutter/material.dart';

import '../../auth/model/api_result.dart';
import '../model/work_log.dart';
import '../repository/work_log_repository.dart';

enum WorkLogApprovalLoadState { initial, loading, success, error }

/// Owns the timesheet approval queue for the Team Leader role - listing
/// every entry submitted against a project they lead and approving/
/// rejecting them. Kept separate from [WorkLogViewModel] (the Employee "my
/// timesheets" state) since the two roles never share a screen.
class WorkLogApprovalViewModel extends ChangeNotifier {
  final WorkLogRepository _repository;

  WorkLogApprovalViewModel({required WorkLogRepository repository})
      : _repository = repository;

  WorkLogApprovalLoadState _loadState = WorkLogApprovalLoadState.initial;
  List<WorkLog> _workLogs = [];
  String? _errorMessage;

  WorkLogApprovalLoadState get loadState => _loadState;
  List<WorkLog> get workLogs => _workLogs;
  String? get errorMessage => _errorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = WorkLogApprovalLoadState.initial;
    _workLogs = [];
    _errorMessage = null;
    _isProcessing = false;
    notifyListeners();
  }

  Future<void> fetchWorkLogs({int? moduleId, String? status}) async {
    _loadState = WorkLogApprovalLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getWorkLogsForApproval(
      moduleId: moduleId,
      status: status,
    );

    if (result.success) {
      _workLogs = (result.data as List<WorkLog>?) ?? [];
      _loadState = WorkLogApprovalLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = WorkLogApprovalLoadState.error;
    }

    notifyListeners();
  }

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  Future<ApiResult> approveWorkLog(int id) async {
    _isProcessing = true;
    notifyListeners();

    final result = await _repository.approveWorkLog(id);
    _applyUpdate(result, id);

    _isProcessing = false;
    notifyListeners();
    return result;
  }

  Future<ApiResult> rejectWorkLog(int id, String rejectionReason) async {
    _isProcessing = true;
    notifyListeners();

    final result = await _repository.rejectWorkLog(id, rejectionReason);
    _applyUpdate(result, id);

    _isProcessing = false;
    notifyListeners();
    return result;
  }

  void _applyUpdate(ApiResult result, int id) {
    if (!result.success) return;
    final updated = result.data as WorkLog?;
    if (updated == null) return;
    _workLogs = _workLogs.map((w) => w.id == id ? updated : w).toList();
  }
}
