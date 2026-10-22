/// Mirrors the backend's `WorkLogReminderResponse` (see `GET
/// /api/work-logs/reminder`) - [missingDayLabel] is null when the previous
/// working day's entry isn't missing (or there is no previous working day to
/// check, e.g. today is Monday), in which case [TimesheetListScreen] shows no
/// popup.
class WorkLogReminder {
  final String? missingDayLabel;

  const WorkLogReminder({this.missingDayLabel});

  bool get hasPendingDay => missingDayLabel != null;

  factory WorkLogReminder.fromJson(Map<String, dynamic> json) {
    return WorkLogReminder(
      missingDayLabel: json['missingDayLabel'] as String?,
    );
  }
}
