import '../../../core/utils/validators.dart';
import '../../activities/model/activity.dart';
import '../../projects/model/project_member_option.dart';

class ModuleValidator {
  ModuleValidator._();

  static String? moduleName(String? value) {
    return Validators.requiredField(value, 'Module Name');
  }

  static String? buildingClassification(String? value) {
    return Validators.requiredField(value, 'Building Classification');
  }

  static String? structureClassification(String? value) {
    return Validators.requiredField(value, 'Structure Classification');
  }

  static String? numberOfFloors(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Number of Floors is required';
    }
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      return 'Number of Floors must be a whole number';
    }
    if (parsed < 1) {
      return 'Number of Floors must be at least 1';
    }
    return null;
  }

  static String? area(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Area is required';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) {
      return 'Area must be a number';
    }
    if (parsed <= 0) {
      return 'Area must be greater than 0';
    }
    return null;
  }

  /// Validates one box of the Hours/Minutes/Seconds duration input - each
  /// box is required and must be a non-negative whole number, with no
  /// digit-count limit.
  static String? durationField(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      return '$fieldName must be a whole number';
    }
    if (parsed < 0) {
      return '$fieldName cannot be negative';
    }
    return null;
  }

  /// Same as [durationField] but additionally caps the value at 59 - for the
  /// Minutes/Seconds boxes of the H:M:S duration input, which shouldn't be
  /// allowed to reach 60 (that would be a whole extra hour/minute).
  static String? minutesOrSeconds(String? value, String fieldName) {
    final baseError = durationField(value, fieldName);
    if (baseError != null) return baseError;
    final parsed = int.parse(value!.trim());
    if (parsed > 59) {
      return '$fieldName cannot exceed 59';
    }
    return null;
  }

  static String? teamLeader(ProjectMemberOption? value) {
    if (value == null) {
      return 'Team Leader is required';
    }
    return null;
  }

  static String? employees(List<ProjectMemberOption> value) {
    if (value.isEmpty) {
      return 'At least one Employee is required';
    }
    return null;
  }

  static String? billableActivities(List<Activity> value) {
    if (value.isEmpty) {
      return 'At least one Billable Activity is required';
    }
    return null;
  }

  static String? nonBillableActivities(List<Activity> value) {
    if (value.isEmpty) {
      return 'At least one Non-Billable Activity is required';
    }
    return null;
  }

  static String? reasonForChange(String? value) {
    return Validators.requiredField(value, 'Reason for change');
  }

  /// Total minutes represented by an Hours/Minutes/Seconds trio of boxes,
  /// rounded to the nearest minute - shared by Create Project/Module and
  /// Edit Module's Revised Working Hours, both of which treat this as a
  /// genuine new total (Edit Module replaces the module's estimate outright
  /// with whatever's entered here, not an amount added on top of it - see
  /// [EditModuleScreen._submit]). Returns null if any box isn't a valid
  /// non-negative whole number (the individual [durationField]/
  /// [minutesOrSeconds] validators on each box surface that error first).
  static int? durationBoxesToMinutes(
    String? hoursText,
    String? minutesText,
    String? secondsText,
  ) {
    final hours = int.tryParse((hoursText ?? '').trim());
    final minutes = int.tryParse((minutesText ?? '').trim());
    final seconds = int.tryParse((secondsText ?? '').trim());
    if (hours == null || minutes == null || seconds == null) return null;
    if (hours < 0 || minutes < 0 || seconds < 0) return null;
    final totalSeconds = hours * 3600 + minutes * 60 + seconds;
    return (totalSeconds / 60).round();
  }

  /// Estimated/Revised Working Hours is mandatory both on creation and on
  /// Edit Module's Revised Working Hours - a module must always have at
  /// least 15 minutes of estimated working hours. [fieldName] lets each
  /// caller's error text match its own field label ("Estimated Working
  /// Hours" on Create Project/Module, "Revised Working Hours" on Edit
  /// Module). Distinguishes "nothing entered" (all three boxes at 0) from
  /// "entered but too short" so the message matches what the user actually
  /// did.
  static String? estimatedWorkingHoursMinimum(int? totalMinutes, String fieldName) {
    if (totalMinutes == null || totalMinutes == 0) {
      return '$fieldName is required';
    }
    if (totalMinutes < 15) {
      return '$fieldName must be at least 15 minutes';
    }
    return null;
  }

  /// Caps the estimated minutes at 24h per day of the module's start-to-end
  /// range (inclusive) - e.g. a 2-day timeline allows at most 48 hours.
  /// Checked in minutes so a sub-hour revision is compared precisely.
  /// Skips silently when any input is missing/invalid so the individual
  /// required-field validators surface their own errors first.
  ///
  /// Shared by both Create Project/Module (where the caller treats a
  /// non-null result as a hard block) and Edit Module's Revised Working
  /// Hours (where the caller only checks `!= null` to show a non-blocking
  /// warning dialog with its own separate copy).
  static String? estimatedMinutesWithinTimeline(
    int? totalMinutes,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    if (totalMinutes == null || startDate == null || endDate == null) return null;
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final days = end.difference(start).inDays + 1;
    if (days <= 0) return null;
    final maxHours = days * 24;
    if (totalMinutes > maxHours * 60) {
      return 'Estimated hours cannot exceed $maxHours '
          '($days day${days == 1 ? '' : 's'} between Start and End Date)';
    }
    return null;
  }

  /// Only enforced on creation ([CreateProjectScreen]) - [EditModuleScreen]/
  /// [EditProjectScreen] never call this, so existing modules with
  /// historical start dates remain editable.
  static String? startDate(DateTime? value) {
    if (value == null) {
      return 'Start Date is required';
    }
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    if (value.isBefore(startOfToday)) {
      return 'Start Date cannot be in the past';
    }
    return null;
  }

  static String? endDate(DateTime? value, DateTime? startDate) {
    if (value == null) {
      return 'End Date is required';
    }
    if (startDate != null && value.isBefore(startDate)) {
      return 'End Date must be on or after Start Date';
    }
    return null;
  }
}
