import 'package:flutter/material.dart';

import '../../auth/model/api_result.dart';
import '../model/billing_entry.dart';
import '../model/update_billing_status_request.dart';
import '../repository/billing_repository.dart';

enum BillingLoadState { initial, loading, success, error }

/// Owns Billing Management state (Captain / Project Controller only) -
/// every project's billing status, and updating it.
class BillingViewModel extends ChangeNotifier {
  final BillingRepository _repository;

  BillingViewModel({required BillingRepository repository})
      : _repository = repository;

  BillingLoadState _loadState = BillingLoadState.initial;
  List<BillingEntry> _entries = [];
  String? _errorMessage;

  BillingLoadState get loadState => _loadState;
  List<BillingEntry> get entries => _entries;
  String? get errorMessage => _errorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = BillingLoadState.initial;
    _entries = [];
    _errorMessage = null;
    _isSaving = false;
    notifyListeners();
  }

  Future<void> fetchBillingList() async {
    _loadState = BillingLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getBillingList();

    if (result.success) {
      _entries = (result.data as List<BillingEntry>?) ?? [];
      _loadState = BillingLoadState.success;
    } else {
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
    _isSaving = true;
    notifyListeners();

    final result = await _repository.updateBillingStatus(moduleId, request);

    if (result.success) {
      final updated = result.data as BillingEntry?;
      if (updated != null) {
        _entries = _entries
            .map((e) => e.moduleId == updated.moduleId ? updated : e)
            .toList();
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }
}
