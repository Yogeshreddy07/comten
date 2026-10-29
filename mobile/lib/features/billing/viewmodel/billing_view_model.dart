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
  Future<void>? _pendingFetch;
  bool _hasLoaded = false;
  bool _isRefreshing = false;
  bool _disposed = false;
  bool get isRefreshing => _isRefreshing;

  BillingLoadState get loadState => _loadState;
  List<BillingEntry> get entries => _entries;
  String? get errorMessage => _errorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _session++;
    _revision++;
    _pendingFetch = null;
    _hasLoaded = false;
    _isRefreshing = false;
    _loadState = BillingLoadState.initial;
    _entries = [];
    _errorMessage = null;
    _isSaving = false;
    notifyListeners();
  }

  Future<void> fetchBillingList() {
    if (_disposed) return Future.value();
    if (_pendingFetch != null) return _pendingFetch!;
    final session = _session, revision = _revision;
    late final Future<void> pending;
    pending = _fetch(session, revision).whenComplete(() {
      if (identical(_pendingFetch, pending)) _pendingFetch = null;
    });
    _pendingFetch = pending;
    return pending;
  }

  Future<void> _fetch(int session, int revision) async {
    _isRefreshing = true;
    if (!_hasLoaded) _loadState = BillingLoadState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _repository.getBillingList();
      if (_disposed || session != _session || revision != _revision) return;
      if (result.success) {
        _entries = (result.data as List<BillingEntry>?) ?? [];
        _hasLoaded = true;
        _loadState = BillingLoadState.success;
      } else {
        _entries = [];
        _hasLoaded = false;
        _errorMessage = result.message;
        _loadState = BillingLoadState.error;
      }
    } catch (_) {
      if (_disposed || session != _session || revision != _revision) return;
      _entries = [];
      _hasLoaded = false;
      _errorMessage = 'Unable to connect to server.';
      _loadState = BillingLoadState.error;
    } finally {
      if (!_disposed && session == _session && revision == _revision) {
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  Future<ApiResult> updateBillingStatus(
    int moduleId,
    UpdateBillingStatusRequest request,
  ) async {
    if (_isSaving) {
      return ApiResult(success: false, message: 'Already saving...');
    }
    final session = _session;
    _revision++;
    _pendingFetch = null;
    _isRefreshing = false;
    _isSaving = true;
    notifyListeners();
    try {
      final result = await _repository.updateBillingStatus(moduleId, request);
      if (_disposed || session != _session) {
        return ApiResult(success: false, message: 'Session changed.');
      }
      _revision++;
      _pendingFetch = null;
      _isRefreshing = false;
      if (result.success) {
        final updated = result.data as BillingEntry?;
        if (updated != null) {
          _entries = _entries
              .map((e) => e.moduleId == updated.moduleId ? updated : e)
              .toList();
        }
      }
      return result;
    } catch (_) {
      return ApiResult(success: false, message: 'Unable to connect to server.');
    } finally {
      if (!_disposed && session == _session) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    super.dispose();
  }
}
