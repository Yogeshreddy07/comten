import '../../../core/services/performance_trace.dart';

import '../../auth/model/api_result.dart';
import '../model/project_change_request.dart';
import '../model/project_deactivation_request.dart';
import '../model/submit_change_request.dart';
import '../repository/approval_repository.dart';

enum ApprovalLoadState { initial, loading, success, error }

/// Owns the Approval module's state (Captain's decision queue, plus the
/// Project Controller's submit action) - the list of `ProjectChangeRequest`s,
/// the list of `ProjectDeactivationRequest`s, and their
/// approve/reject/submit mutations.
class ApprovalViewModel extends PerformanceNotifier {
  final ApprovalRepository _repository;

  ApprovalViewModel({required ApprovalRepository repository})
      : _repository = repository;

  ApprovalLoadState _loadState = ApprovalLoadState.initial;
  List<ProjectChangeRequest> _requests = [];
  List<ProjectDeactivationRequest> _deactivationRequests = [];
  String? _errorMessage;

  ApprovalLoadState get loadState => _loadState;
  List<ProjectChangeRequest> get requests => _requests;
  List<ProjectDeactivationRequest> get deactivationRequests => _deactivationRequests;
  String? get errorMessage => _errorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = ApprovalLoadState.initial;
    _requests = [];
    _deactivationRequests = [];
    _errorMessage = null;
    _isSaving = false;
    notifyListeners();
  }

  /// Project status changes are direct manager actions. Legacy deactivation
  /// requests no longer belong in the decision queue.
  Future<void> fetchChangeRequests() async {
    _loadState = ApprovalLoadState.loading;
    _errorMessage = null;
    _deactivationRequests = [];
    notifyListeners();

    final result = await _repository.getChangeRequests();
    if (result.success) {
      _requests = (result.data as List<ProjectChangeRequest>?) ?? [];
      _loadState = ApprovalLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = ApprovalLoadState.error;
    }
    notifyListeners();
  }

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  Future<ApiResult> submitChangeRequest(SubmitChangeRequest request) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.submitChangeRequest(request);

    _isSaving = false;
    notifyListeners();
    return result;
  }

  Future<ApiResult> approve(int id, String reason) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.approve(id, reason);
    if (result.success) {
      final updated = result.data as ProjectChangeRequest?;
      if (updated != null) {
        _requests = _requests.map((r) => r.id == updated.id ? updated : r).toList();
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }

  Future<ApiResult> reject(int id, String reason) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.reject(id, reason);
    if (result.success) {
      final updated = result.data as ProjectChangeRequest?;
      if (updated != null) {
        _requests = _requests.map((r) => r.id == updated.id ? updated : r).toList();
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }

  Future<ApiResult> approveDeactivation(int id, String reason) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.approveDeactivation(id, reason);
    if (result.success) {
      final updated = result.data as ProjectDeactivationRequest?;
      if (updated != null) {
        _deactivationRequests = _deactivationRequests
            .map((r) => r.id == updated.id ? updated : r)
            .toList();
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }

  Future<ApiResult> rejectDeactivation(int id, String reason) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.rejectDeactivation(id, reason);
    if (result.success) {
      final updated = result.data as ProjectDeactivationRequest?;
      if (updated != null) {
        _deactivationRequests = _deactivationRequests
            .map((r) => r.id == updated.id ? updated : r)
            .toList();
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }
}
