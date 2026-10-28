import '../../../core/utils/validators.dart';
import '../../activities/model/activity.dart';
import '../../modules/model/module_list_item.dart';
import '../../projects/model/project_list_item.dart';
import 'work_log_duration_formatter.dart';

class TimesheetValidator {
  TimesheetValidator._();

  static String? project(ProjectListItem? value) {
    if (value == null) {
      return 'Project is required';
    }
    return null;
  }

  static String? module(ModuleListItem? value) {
    if (value == null) {
      return 'Module is required';
    }
    if (value.status != 'IN_PROGRESS' || value.billingStatus == 'FULL_PAYMENT_RECEIVED') {
      return 'Select an in-progress module. Completed modules cannot log hours.';
    }
    return null;
  }

  /// Monday of the current week (date-only) - the earliest day still open
  /// for logging. Mirrors `WorkLogServiceImpl#validateWorkWeekWindow`.
  static DateTime currentWeekMonday() {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return startOfToday.subtract(Duration(days: startOfToday.weekday - 1));
  }

  /// True only on Sunday, when the whole work log window is closed - the
  /// past week locks when Sunday starts and reopens on Monday.
  static bool isLoggingClosedToday() =>
      DateTime.now().weekday == DateTime.sunday;

  /// True once a module's end date has fully passed the current loggable
  /// week (i.e. it falls before this week's Monday) - at that point no day
  /// can ever be picked for it this week, so it should drop out of Work Log
  /// selection entirely (see [SubmitTimesheetScreen._buildBody]'s
  /// `eligibleModules`) rather than being offered with every day disabled.
  /// Naturally reverses itself once the end date is extended past this
  /// week's Monday again - this only ever reads the module's current
  /// [endDate], nothing is cached.
  static bool isModuleExpiredForLogging(DateTime? endDate) {
    if (endDate == null) return false;
    final endOfDay = DateTime(endDate.year, endDate.month, endDate.day);
    return endOfDay.isBefore(currentWeekMonday());
  }

  static String? workDate(
    DateTime? value, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (value == null) {
      return 'Work Date is required';
    }
    if (isLoggingClosedToday()) {
      return 'Work logs cannot be submitted on Sunday - the window reopens on Monday';
    }
    final today = DateTime.now();
    final endOfToday = DateTime(today.year, today.month, today.day, 23, 59, 59);
    if (value.isAfter(endOfToday)) {
      return 'Work Date cannot be in the future';
    }
    if (value.weekday == DateTime.sunday) {
      return 'Work Date cannot be a Sunday';
    }
    if (value.isBefore(currentWeekMonday())) {
      return 'Work logs can only be submitted for the current week (from Monday)';
    }
    if (startDate != null) {
      final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
      if (value.isBefore(startOfDay)) {
        return 'Work Date cannot be before the module\'s start date';
      }
    }
    if (endDate != null) {
      final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      if (value.isAfter(endOfDay)) {
        return 'Work Date cannot be after the module\'s end date';
      }
    }
    return null;
  }

  static String? durationSeconds(int totalSeconds, {String fieldLabel = 'Hours Worked'}) {
    if (totalSeconds < 900) {
      return '$fieldLabel must be at least ${WorkLogDurationFormatter.format(900)}';
    }
    if (totalSeconds > 86400) {
      return '$fieldLabel cannot exceed ${WorkLogDurationFormatter.format(86400)} in a day';
    }
    return null;
  }

  /// Validates one category (Billable or Non-Billable) end to end: its
  /// Activities list and its Hours Worked field must be filled together -
  /// never one without the other - and once both are present, the hours
  /// value itself must fall in the normal 15min..24h range. Neither being
  /// filled is fine (there's no compulsion to use both categories) - see
  /// [activitySelection] for the "at least one of the two" rule.
  static String? categoryHoursWorked({
    required bool hasActivities,
    required int seconds,
    required String hoursFieldLabel,
    required String activityFieldLabel,
  }) {
    final hasHours = seconds > 0;
    if (hasActivities && !hasHours) {
      return '$hoursFieldLabel is required when $activityFieldLabel are selected';
    }
    if (hasHours && !hasActivities) {
      return 'Select at least one $activityFieldLabel to log $hoursFieldLabel';
    }
    if (!hasActivities) {
      return null;
    }
    return durationSeconds(seconds, fieldLabel: hoursFieldLabel);
  }

  /// The combined Billable + Non-Billable total still can't exceed a day -
  /// mirrors the old single Hours Worked field's upper bound, now checked
  /// across both fields together.
  static String? combinedDurationSeconds(int billableSeconds, int nonBillableSeconds) {
    final total = billableSeconds + nonBillableSeconds;
    if (total > 86400) {
      return 'Total Hours Worked cannot exceed ${WorkLogDurationFormatter.format(86400)} in a day';
    }
    return null;
  }

  static String? workDone(String? value) {
    return Validators.requiredField(value, 'Work Done');
  }

  static String? activitySelection(
    List<Activity> billableActivities,
    List<Activity> nonBillableActivities,
  ) {
    if (billableActivities.isEmpty && nonBillableActivities.isEmpty) {
      return 'Select at least one Billable or Non-Billable activity';
    }
    return null;
  }

  static String? validateMinutes(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return null;
    if (parsed < 0 || parsed > 59) {
      return "Minutes shouldn't exceed more than 59";
    }
    return null;
  }

  static String? validateSeconds(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return null;
    if (parsed < 0 || parsed > 59) {
      return "Seconds should not be more than 59";
    }
    return null;
  }
}
