import '../../../core/services/performance_trace.dart';

import '../../auth/model/api_result.dart';
import '../model/billing_entry.dart';
import '../model/update_billing_status_request.dart';
import '../repository/billing_repository.dart';

enum BillingLoadState { initial, loading, success, error }

/// Owns Billing Management state (Captain / Project Controller only) -
/// every project's billing status, and updating it.
class BillingViewModel extends PerformanceNotifier {
  final BillingRepository _repository;

  BillingViewModel({required BillingRepository repository})
    : _repository = repository;

  BillingLoadState _loadState = BillingLoadState.initial;
  List<BillingEntry> _entries = [];
  String? _errorMessage;
  int _session = 0;
  int _revision = 0;
  Future<void>? _pendingLoad;

  BillingLoadState get loadState => _loadState;
  List<BillingEntry> get entries => _entries;
  String? get errorMessage => _errorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _session++;
    _revision++;
    _pendingLoad = null;
    _loadState = BillingLoadState.initial;
    _entries = [];
    _errorMessage = null;
    _isSaving = false;
    notifyListeners();
  }

  Future<void> fetchBillingList() {
    final pending = _pendingLoad;
    if (pending != null) return pending;
    late final Future<void> request;
    request = _fetchBillingList().whenComplete(() {
      if (identical(_pendingLoad, request)) _pendingLoad = null;
    });
    _pendingLoad = request;
    return request;
  }

  Future<void> _fetchBillingList() async {
    final session = _session;
    final revision = _revision;
    // Re-entry always refreshes from the server, while the current session's
    // already-loaded content remains visible instead of a blank full loader.
    if (_loadState != BillingLoadState.success) {
      _loadState = BillingLoadState.loading;
    }
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getBillingList();
    if (session != _session || revision != _revision) return;

    if (result.success) {
      _entries = (result.data as List<BillingEntry>?) ?? [];
      _loadState = BillingLoadState.success;
    } else {
      _entries = [];
      _errorMessage = result.message;
      _loadState = BillingLoadState.error;
    }

    notifyListeners();
  }

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  Future<ApiResult> updateBillingStatus(
    int moduleId,
    UpdateBillingStatusRequest request,
  ) async {
    if (_isSaving) {
      return ApiResult(
        success: false,
        message: 'A billing update is already in progress.',
      );
    }
    final session = _session;
    _isSaving = true;
    notifyListeners();

    try {
      final result = await _repository.updateBillingStatus(moduleId, request);
      if (session != _session) return result;

      if (result.success) {
        _revision++;
        _loadState = BillingLoadState.success;
        final updated = result.data as BillingEntry?;
        if (updated != null) {
          _entries = _entries
              .map((e) => e.moduleId == updated.moduleId ? updated : e)
              .toList();
        }
      }

      return result;
    } finally {
      if (session == _session) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }
}
