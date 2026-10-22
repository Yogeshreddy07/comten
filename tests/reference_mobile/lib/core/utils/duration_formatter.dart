class DurationFormatter {
  DurationFormatter._();

  /// Formats a total-minutes duration as a human-readable string - e.g.
  /// 90 -> "1 hour 30 minutes", 120 -> "2 hours", 30 -> "30 minutes".
  /// Whichever of hours/minutes is zero is omitted rather than printed as
  /// "0 hours"/"0 minutes". Returns null for a null input.
  static String? humanReadable(int? totalMinutes) {
    if (totalMinutes == null) return null;
    final minutes = totalMinutes < 0 ? 0 : totalMinutes;
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (hours == 0 && remainingMinutes == 0) return '0 minutes';

    final parts = <String>[
      if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
      if (remainingMinutes > 0)
        '$remainingMinutes ${remainingMinutes == 1 ? 'minute' : 'minutes'}',
    ];
    return parts.join(' ');
  }
}
