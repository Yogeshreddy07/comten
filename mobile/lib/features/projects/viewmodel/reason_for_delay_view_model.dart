import '../../../core/services/performance_trace.dart';

import '../../auth/model/api_result.dart';
import '../../modules/model/module_list_item.dart';
import '../../modules/repository/module_repository.dart';
import '../../notifications/model/submit_delay_request.dart';
import '../../notifications/repository/notification_repository.dart';

enum ReasonForDelayLoadState { initial, loading, success, error }

/// Owns the Team Lead's Reason for Delay screen state - the active modules
/// they lead (for the module picker, see
/// `ModuleServiceImpl#getLedModules`), and submitting a delay request (see
/// `NotificationServiceImpl#submitDelayRequest`), which notifies every
/// Project Controller. Kept separate from [StatusUpdateViewModel] (a
/// different Team Lead screen with its own, differently-filtered led-modules
/// list) since the two screens have no other state in common.
class ReasonForDelayViewModel extends PerformanceNotifier {
  final ModuleRepository _moduleRepository;
  final NotificationRepository _notificationRepository;

  ReasonForDelayViewModel({
    required ModuleRepository moduleRepository,
    required NotificationRepository notificationRepository,
  })  : _moduleRepository = moduleRepository,
        _notificationRepository = notificationRepository;

  ReasonForDelayLoadState _loadState = ReasonForDelayLoadState.initial;
  List<ModuleListItem> _ledModules = [];
  String? _errorMessage;

  ReasonForDelayLoadState get loadState => _loadState;
  List<ModuleListItem> get ledModules => _ledModules;
  String? get errorMessage => _errorMessage;

  Future<void> fetchLedModules() async {
    _loadState = ReasonForDelayLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _moduleRepository.getLedModules();

    if (result.success) {
      _ledModules = (result.data as List<ModuleListItem>?) ?? [];
      _loadState = ReasonForDelayLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = ReasonForDelayLoadState.error;
    }

    notifyListeners();
  }

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  Future<ApiResult> submitDelayRequest(int moduleId, String reason) async {
    _isSubmitting = true;
    notifyListeners();

    final result = await _notificationRepository.submitDelayRequest(
      SubmitDelayRequest(moduleId: moduleId, reason: reason),
    );

    _isSubmitting = false;
    notifyListeners();
    return result;
  }
}
