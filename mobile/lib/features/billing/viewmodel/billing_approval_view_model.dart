import '../../../core/services/performance_trace.dart';

import '../../auth/model/api_result.dart';
import '../model/billing_status_change_request.dart';
import '../repository/billing_repository.dart';

enum BillingApprovalLoadState { initial, loading, success, error }

/// Owns the Billing Approval module's state (Captain's decision queue over
/// Project Controller requests to revert a completed billing project back
/// to Pending) - the list of [BillingStatusChangeRequest]s and
/// approve/reject mutations.
class BillingApprovalViewModel extends PerformanceNotifier {
  final BillingRepository _repository;

  BillingApprovalViewModel({required BillingRepository repository})
      : _repository = repository;

  BillingApprovalLoadState _loadState = BillingApprovalLoadState.initial;
  List<BillingStatusChangeRequest> _requests = [];
  String? _errorMessage;

  BillingApprovalLoadState get loadState => _loadState;
  List<BillingStatusChangeRequest> get requests => _requests;
  String? get errorMessage => _errorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = BillingApprovalLoadState.initial;
    _requests = [];
    _errorMessage = null;
    _isSaving = false;
    notifyListeners();
  }

  Future<void> fetchChangeRequests() async {
    _loadState = BillingApprovalLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getBillingStatusChangeRequests();

    if (result.success) {
      _requests = (result.data as List<BillingStatusChangeRequest>?) ?? [];
      _loadState = BillingApprovalLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = BillingApprovalLoadState.error;
    }

    notifyListeners();
  }

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  Future<ApiResult> approve(int id, String reason) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.approveBillingStatusChangeRequest(id, reason);
    if (result.success) {
      final updated = result.data as BillingStatusChangeRequest?;
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

    final result = await _repository.rejectBillingStatusChangeRequest(id, reason);
    if (result.success) {
      final updated = result.data as BillingStatusChangeRequest?;
      if (updated != null) {
        _requests = _requests.map((r) => r.id == updated.id ? updated : r).toList();
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }
}
