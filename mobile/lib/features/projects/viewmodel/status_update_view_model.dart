import 'package:flutter/material.dart';

import '../../auth/model/api_result.dart';
import '../../modules/model/module_list_item.dart';
import '../../modules/repository/module_repository.dart';

enum StatusUpdateLoadState { initial, loading, success, error }

/// Owns the Team Lead's Status Update screen state - the modules they lead
/// that are eligible for a work-stage change (see
/// `ModuleServiceImpl#getCompletedLedModules`: Not Started, In Progress, or
/// Completed modules, all movable into Billing, plus anything already in
/// Billing so it can be moved back to WIP), and toggling that WIP/Billing
/// work stage (see `ModuleServiceImpl#updateWorkStage` - a Completed module
/// can never move straight back to WIP, unlike Not Started/In Progress
/// ones).
class StatusUpdateViewModel extends ChangeNotifier {
  final ModuleRepository _repository;

  StatusUpdateViewModel({required ModuleRepository repository})
      : _repository = repository;

  StatusUpdateLoadState _loadState = StatusUpdateLoadState.initial;
  List<ModuleListItem> _ledModules = [];
  String? _errorMessage;

  StatusUpdateLoadState get loadState => _loadState;
  List<ModuleListItem> get ledModules => _ledModules;
  String? get errorMessage => _errorMessage;

  Future<void> fetchLedModules() async {
    _loadState = StatusUpdateLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getCompletedLedModules();

    if (result.success) {
      _ledModules = (result.data as List<ModuleListItem>?) ?? [];
      _loadState = StatusUpdateLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = StatusUpdateLoadState.error;
    }

    notifyListeners();
  }

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  Future<ApiResult> updateWorkStage(int moduleId, String workStage) async {
    final module = _ledModules.where((m) => m.id == moduleId).firstOrNull;
    if (workStage == 'WIP' && module?.status == 'COMPLETED') {
      return ApiResult(success: false,
          message: 'This module is already completed and cannot be moved back to WIP.');
    }
    if (_isSaving) {
      return ApiResult(success: false, message: 'A status update is already in progress.');
    }
    _isSaving = true;
    notifyListeners();

    final result = await _repository.updateWorkStage(moduleId, workStage);

    if (result.success) {
      _ledModules = _ledModules
          .map((m) => m.id == moduleId ? m.copyWith(workStage: workStage) : m)
          .toList();
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }
}
