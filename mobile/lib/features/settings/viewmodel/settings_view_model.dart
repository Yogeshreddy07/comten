import '../../../core/services/performance_trace.dart';

import '../../auth/model/api_result.dart';
import '../../auth/repository/auth_repository.dart';
import '../model/user_settings.dart';

enum SettingsLoadState { initial, loading, success, error }

/// Owns the Settings screen's account/security state - fetching the current
/// user's settings and delegating password changes and logout to
/// [AuthRepository] (these are `/api/auth/**` endpoints, not a separate
/// domain, so no dedicated repository is introduced here). App lock
/// (PIN/biometric) stays on [AuthViewModel] since that's a device-level
/// setting stored locally, not an account/backend concern.
class SettingsViewModel extends PerformanceNotifier {
  final AuthRepository _repository;

  SettingsViewModel({required AuthRepository repository})
      : _repository = repository;

  SettingsLoadState _loadState = SettingsLoadState.initial;
  UserSettings? _settings;
  String? _errorMessage;
  bool _isSaving = false;

  SettingsLoadState get loadState => _loadState;
  UserSettings? get settings => _settings;
  String? get errorMessage => _errorMessage;
  bool get isSaving => _isSaving;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = SettingsLoadState.initial;
    _settings = null;
    _errorMessage = null;
    _isSaving = false;
    notifyListeners();
  }

  Future<void> fetchSettings() async {
    _loadState = SettingsLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getSettings();

    if (result.success && result.data != null) {
      _settings = UserSettings.fromJson(result.data as Map<String, dynamic>);
      _loadState = SettingsLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = SettingsLoadState.error;
    }

    notifyListeners();
  }

  Future<ApiResult> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    _isSaving = true;
    notifyListeners();
    final result = await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
    _isSaving = false;
    notifyListeners();
    return result;
  }

  Future<ApiResult> logout() {
    return _repository.logout();
  }
}
