import 'package:flutter/material.dart';

import '../model/team_attendance_entry.dart';
import '../repository/attendance_repository.dart';

enum AttendanceTeamLoadState { initial, loading, success, error }

/// Owns the Team Leader's attendance roster view - every member of a
/// project they lead, with their attendance status for a single selected
/// date (defaults to today, see [selectedDate]). Kept separate from
/// [AttendanceViewModel] (the Employee's own check-in/check-out state)
/// since the two roles never share a screen.
class AttendanceTeamViewModel extends ChangeNotifier {
  final AttendanceRepository _repository;

  AttendanceTeamViewModel({required AttendanceRepository repository})
      : _repository = repository;

  AttendanceTeamLoadState _loadState = AttendanceTeamLoadState.initial;
  List<TeamAttendanceEntry> _records = [];
  String? _errorMessage;
  DateTime _selectedDate = DateTime.now();

  AttendanceTeamLoadState get loadState => _loadState;
  List<TeamAttendanceEntry> get records => _records;
  String? get errorMessage => _errorMessage;
  DateTime get selectedDate => _selectedDate;

  /// Clears this ViewModel's cached state on logout/new login so the next
  /// user never sees the previous user's data before their own fetch runs.
  void reset() {
    _loadState = AttendanceTeamLoadState.initial;
    _records = [];
    _errorMessage = null;
    _selectedDate = DateTime.now();
    notifyListeners();
  }

  Future<void> fetchTeamAttendance({DateTime? date}) async {
    if (date != null) _selectedDate = date;

    _loadState = AttendanceTeamLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _repository.getTeamAttendance(date: _selectedDate);

    if (result.success) {
      _records = (result.data as List<TeamAttendanceEntry>?) ?? [];
      _loadState = AttendanceTeamLoadState.success;
    } else {
      _errorMessage = result.message;
      _loadState = AttendanceTeamLoadState.error;
    }

    notifyListeners();
  }
}
