/// Renders a total-seconds duration value (e.g. `1200`) as a
/// human-readable duration (e.g. "20 Minutes") - only units with a
/// non-zero value are shown, matching how the Log Hours screen collects the
/// value as separate Hours/Minutes/Seconds fields.
class WorkLogDurationFormatter {
  WorkLogDurationFormatter._();

  static String format(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final parts = <String>[
      if (hours > 0) '$hours ${hours == 1 ? 'Hour' : 'Hours'}',
      if (minutes > 0) '$minutes ${minutes == 1 ? 'Minute' : 'Minutes'}',
      if (seconds > 0) '$seconds ${seconds == 1 ? 'Second' : 'Seconds'}',
    ];

    return parts.isEmpty ? '0 Hours' : parts.join(' ');
  }

  /// Abbreviated variant of [format] (e.g. "8hr 30min 15sec") for the
  /// timesheet list rows, where the full wording overflows the card. Detail
  /// screens and validation messages keep the long form via [format].
  static String formatCompact(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final parts = <String>[
      if (hours > 0) '${hours}hr',
      if (minutes > 0) '${minutes}min',
      if (seconds > 0) '${seconds}sec',
    ];

    return parts.isEmpty ? '0hr' : parts.join(' ');
  }
}
