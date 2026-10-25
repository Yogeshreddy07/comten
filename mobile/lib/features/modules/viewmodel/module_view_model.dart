import 'package:flutter/material.dart';

import '../../auth/model/api_result.dart';
import '../model/module_list_item.dart';
import '../model/module_summary.dart';
import '../model/update_module_request.dart';
import '../repository/module_repository.dart';

enum ModuleLoadState { initial, loading, success, error }

class ModuleViewModel extends ChangeNotifier {
  final ModuleRepository _repository;

  ModuleViewModel({required ModuleRepository repository})
      : _repository = repository;

  // ---- List (GET /modules?projectId=) - modules for the currently open
  // Project Details screen. ----
  ModuleLoadState _loadState = ModuleLoadState.initial;
  List<ModuleListItem> _modules = [];
  String? _errorMessage;

  ModuleLoadState get loadState => _loadState;
  List<ModuleListItem> get modules => _modules;
  String? get errorMessage => _errorMessage;

  Future<void> fetchModules({int? projectId}) async {
    _loadState = ModuleLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getModules(projectId: projectId);

    if (result.success) {
      _modules = (result.data as List<ModuleListItem>?) ?? [];
      _loadState = ModuleLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = ModuleLoadState.error;
    }

    notifyListeners();
  }

  // ---- Detail (GET /modules/{id}) - one active detail at a time, matching
  // there only ever being one Module Details screen visible in the stack. ----
  ModuleLoadState _detailState = ModuleLoadState.initial;
  ModuleSummary? _selectedModule;
  String? _detailErrorMessage;

  ModuleLoadState get detailState => _detailState;
  ModuleSummary? get selectedModule => _selectedModule;
  String? get detailErrorMessage => _detailErrorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = ModuleLoadState.initial;
    _modules = [];
    _errorMessage = null;
    _detailState = ModuleLoadState.initial;
    _selectedModule = null;
    _detailErrorMessage = null;
    _isSaving = false;
    _isDeactivating = false;
    notifyListeners();
  }

  Future<void> fetchModuleDetails(int id) async {
    _detailState = ModuleLoadState.loading;
    _detailErrorMessage = null;
    notifyListeners();

    final result = await _repository.getModuleDetails(id);

    if (result.success) {
      _selectedModule = result.data as ModuleSummary?;
      _detailState = ModuleLoadState.success;
    } else {
      _detailErrorMessage = result.message;
      _detailState = ModuleLoadState.error;
    }

    notifyListeners();
  }

  // ---- Mutations ----
  bool _isSaving = false;
  bool _isDeactivating = false;

  bool get isSaving => _isSaving;
  bool get isDeactivating => _isDeactivating;

  Future<ApiResult> updateModule(int id, UpdateModuleRequest request) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.updateModule(id, request);

    if (result.success) {
      final updated = result.data as ModuleSummary?;
      if (updated != null) {
        _selectedModule = updated;
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }

  /// Soft-deactivates the module (backend sets status to INACTIVE, the row
  /// stays in the list) - reflects the new status locally in both the
  /// selected detail and the cached list row rather than removing anything.
  Future<ApiResult> deactivateModule(int id) async {
    _isDeactivating = true;
    notifyListeners();

    final result = await _repository.deactivateModule(id);

    if (result.success) {
      _modules = _modules
          .map((m) => m.id == id ? m.copyWith(status: 'INACTIVE') : m)
          .toList();
      if (_selectedModule?.id == id) {
        _selectedModule = _selectedModule!.copyWith(status: 'INACTIVE');
      }
    }

    _isDeactivating = false;
    notifyListeners();
    return result;
  }

  /// Reflect the lifecycle status returned by the server immediately.
  Future<ApiResult> activateModule(int id) async {
    _isDeactivating = true;
    notifyListeners();

    final result = await _repository.activateModule(id);

    if (result.success && result.data is Map) {
      final status = (result.data as Map)['status'] as String? ?? 'NOT_STARTED';
      _modules = _modules.map((m) => m.id == id ? m.copyWith(status: status) : m).toList();
      if (_selectedModule?.id == id) {
        _selectedModule = _selectedModule!.copyWith(status: status);
      }
    }

    _isDeactivating = false;
    notifyListeners();
    return result;
  }

  /// Soft-deletes the module (backend sets `isDeleted` to true; the row is
  /// retained for records but excluded from every future list response) -
  /// removed from the local list immediately.
  Future<ApiResult> deleteModule(int id) async {
    _isDeactivating = true;
    notifyListeners();

    final result = await _repository.deleteModule(id);

    if (result.success) {
      _modules = _modules.where((m) => m.id != id).toList();
    }

    _isDeactivating = false;
    notifyListeners();
    return result;
  }
}
