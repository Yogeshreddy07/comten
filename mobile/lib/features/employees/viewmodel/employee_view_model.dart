import 'package:flutter/material.dart';

import '../../../shared/enums/user_role.dart';
import '../../auth/model/api_result.dart';
import '../model/create_employee_request.dart';
import '../model/employee.dart';
import '../model/update_employee_request.dart';
import '../repository/employee_repository.dart';

enum EmployeeLoadState { initial, loading, success, error }

class EmployeeViewModel extends ChangeNotifier {
  final EmployeeRepository _repository;

  EmployeeViewModel({required EmployeeRepository repository})
      : _repository = repository;

  // ---- List (GET /employees) ----
  EmployeeLoadState _loadState = EmployeeLoadState.initial;
  List<Employee> _employees = [];
  String? _errorMessage;

  EmployeeLoadState get loadState => _loadState;
  List<Employee> get employees => _employees;
  String? get errorMessage => _errorMessage;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = EmployeeLoadState.initial;
    _employees = [];
    _errorMessage = null;
    _isSaving = false;
    _isDeactivating = false;
    notifyListeners();
  }

  /// Pass [roleFilter] to scope the fetched list to a single role; the
  /// caller (the screen) is responsible for passing the same value on every
  /// call, including pull-to-refresh - this ViewModel doesn't remember it,
  /// since a single shared instance is used by both the unrestricted
  /// Employee Management screen and the Captain's Project-Controller-only
  /// screen, and either could be the most recent caller.
  Future<void> fetchEmployees({UserRole? roleFilter}) async {
    _loadState = EmployeeLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getEmployees(role: roleFilter);

    if (result.success) {
      _employees = (result.data as List<Employee>?) ?? [];
      _loadState = EmployeeLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = EmployeeLoadState.error;
    }

    notifyListeners();
  }

  // ---- Mutations ----
  bool _isSaving = false;
  bool _isDeactivating = false;

  bool get isSaving => _isSaving;
  bool get isDeactivating => _isDeactivating;

  Future<ApiResult> createEmployee(CreateEmployeeRequest request) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.createEmployee(request);

    if (result.success) {
      final created = result.data as Employee?;
      if (created != null) {
        _employees = [..._employees, created.copyWith()]
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }

  Future<ApiResult> updateEmployee(int id, UpdateEmployeeRequest request) async {
    _isSaving = true;
    notifyListeners();

    final result = await _repository.updateEmployee(id, request);

    if (result.success) {
      final updated = result.data as Employee?;
      if (updated != null) {
        _employees = _employees
            .map((e) => e.id == updated.id ? updated : e)
            .toList();
      }
    }

    _isSaving = false;
    notifyListeners();
    return result;
  }

  /// Soft-deactivates the account (backend sets isActive=false; the row
  /// stays in the list) - reflects the new state locally rather than
  /// removing the entry.
  Future<ApiResult> deactivateEmployee(int id) async {
    _isDeactivating = true;
    notifyListeners();

    final result = await _repository.deactivateEmployee(id);

    if (result.success) {
      _employees = _employees
          .map((e) => e.id == id ? e.copyWith(isActive: false) : e)
          .toList();
    }

    _isDeactivating = false;
    notifyListeners();
    return result;
  }

  /// Reactivates a previously deactivated account (backend sets
  /// isActive=true) - reflects the new state locally rather than removing
  /// the entry.
  Future<ApiResult> activateEmployee(int id) async {
    _isDeactivating = true;
    notifyListeners();

    final result = await _repository.activateEmployee(id);

    if (result.success) {
      _employees = _employees
          .map((e) => e.id == id ? e.copyWith(isActive: true) : e)
          .toList();
    }

    _isDeactivating = false;
    notifyListeners();
    return result;
  }

  /// Soft-deletes the account (backend sets isDeleted=true, isActive=false;
  /// the row is retained for records but excluded from every future list
  /// response) - removed from the local list immediately so it disappears
  /// from the UI without waiting for a refetch.
  Future<ApiResult> deleteEmployee(int id) async {
    _isDeactivating = true;
    notifyListeners();

    final result = await _repository.deleteEmployee(id);

    if (result.success) {
      _employees = _employees.where((e) => e.id != id).toList();
    }

    _isDeactivating = false;
    notifyListeners();
    return result;
  }
}
