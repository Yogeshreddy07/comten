import '../../../core/services/performance_trace.dart';

import '../../auth/model/api_result.dart';
import '../model/attendance.dart';
import '../model/check_in_request.dart';
import '../model/check_out_request.dart';
import '../repository/attendance_repository.dart';

enum AttendanceLoadState { initial, loading, success, error }

/// Owns the Employee's own attendance state for today - whether they've
/// checked in/out yet, and performing the check-in/check-out actions. The
/// Team Leader's view of their team's history is a separate concern - see
/// [AttendanceTeamViewModel] - since the two roles never share a screen.
class AttendanceViewModel extends PerformanceNotifier {
  final AttendanceRepository _repository;

  AttendanceViewModel({required AttendanceRepository repository})
      : _repository = repository;

  /// Hours checked in with no checkout before the reminder popup is due -
  /// see [isCheckoutOverdue].
  static const checkoutReminderThresholdHours = 9;

  AttendanceLoadState _loadState = AttendanceLoadState.initial;
  Attendance? _today;
  String? _errorMessage;

  AttendanceLoadState get loadState => _loadState;
  Attendance? get today => _today;
  String? get errorMessage => _errorMessage;

  /// Whether today's attendance has been open (checked in, not checked out)
  /// for at least [checkoutReminderThresholdHours] - purely derived from
  /// already-fetched data, never persisted. Drives the checkout reminder
  /// popup shown from the dashboard (see `RoleDashboardScaffold`).
  bool get isCheckoutOverdue {
    final attendance = _today;
    if (attendance == null || attendance.outTime != null) return false;
    return DateTime.now().difference(attendance.inTime).inHours >=
        checkoutReminderThresholdHours;
  }

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = AttendanceLoadState.initial;
    _today = null;
    _errorMessage = null;
    _isSubmitting = false;
    notifyListeners();
  }

  Future<void> fetchTodayAttendance() async {
    _loadState = AttendanceLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getTodayAttendance();

    if (result.success) {
      _today = result.data as Attendance?;
      _loadState = AttendanceLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = AttendanceLoadState.error;
    }

    notifyListeners();
  }

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  Future<ApiResult> checkIn(CheckInRequest request) async {
    _isSubmitting = true;
    notifyListeners();

    final result = await _repository.checkIn(request);
    if (result.success) {
      _today = result.data as Attendance?;
    }

    _isSubmitting = false;
    notifyListeners();
    return result;
  }

  Future<ApiResult> checkOut(CheckOutRequest request) async {
    _isSubmitting = true;
    notifyListeners();

    final result = await _repository.checkOut(request);
    if (result.success) {
      _today = result.data as Attendance?;
    }

    _isSubmitting = false;
    notifyListeners();
    return result;
  }
}
