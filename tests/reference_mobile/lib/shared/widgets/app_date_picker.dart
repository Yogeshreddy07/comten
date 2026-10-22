import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/snackbar_util.dart';

class AppDatePicker extends StatelessWidget {
  final String label;
  final DateTime? value;
  final void Function(DateTime date) onChanged;
  final String? Function(DateTime? value)? validator;
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// Optional per-day filter forwarded to [showDatePicker] - e.g. the Work
  /// Log form disables Sundays. Days failing the predicate are unselectable.
  final bool Function(DateTime day)? selectableDayPredicate;

  /// When false, the field is greyed out and tapping it does nothing - e.g.
  /// the Work Log form disables the date field until a module is picked, so
  /// the calendar never opens with a stale (module-less) first/last range.
  final bool enabled;

  /// Shown instead of the usual "Select date" hint while [enabled] is false.
  final String disabledHintText;

  const AppDatePicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.validator,
    this.firstDate,
    this.lastDate,
    this.selectableDayPredicate,
    this.enabled = true,
    this.disabledHintText = 'Select date',
  });

  Future<DateTime?> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final effectiveFirstDate = firstDate ?? DateTime(now.year - 5);
    final effectiveLastDate = lastDate ?? DateTime(now.year + 10);

    // A range with no valid days (e.g. a module that ended before this
    // week's window opened) can't show a calendar at all. Tell the user why
    // instead of leaving the tap a silent no-op - a bare `return null` here
    // previously left the field looking tappable but permanently inert.
    if (effectiveLastDate.isBefore(effectiveFirstDate)) {
      _showNoSelectableDateMessage(context);
      return null;
    }

    // showDatePicker asserts initialDate falls within [firstDate, lastDate].
    // Defaulting to `now` breaks that whenever firstDate is in the future -
    // e.g. an End Date field constrained by an already-picked, later-than-
    // today Start Date - silently preventing the calendar from opening.
    // Clamp instead of assuming `now` is always a valid initial value.
    var initialDate = value ?? now;
    if (initialDate.isBefore(effectiveFirstDate)) {
      initialDate = effectiveFirstDate;
    } else if (initialDate.isAfter(effectiveLastDate)) {
      initialDate = effectiveLastDate;
    }

    // The same assertion applies to selectableDayPredicate(initialDate) -
    // walk backwards, then forwards, to the nearest selectable day in range.
    final predicate = selectableDayPredicate;
    if (predicate != null && !predicate(initialDate)) {
      DateTime? candidate;
      var day = initialDate.subtract(const Duration(days: 1));
      while (!day.isBefore(effectiveFirstDate)) {
        if (predicate(day)) {
          candidate = day;
          break;
        }
        day = day.subtract(const Duration(days: 1));
      }
      if (candidate == null) {
        day = initialDate.add(const Duration(days: 1));
        while (!day.isAfter(effectiveLastDate)) {
          if (predicate(day)) {
            candidate = day;
            break;
          }
          day = day.add(const Duration(days: 1));
        }
      }
      if (candidate == null) {
        _showNoSelectableDateMessage(context);
        return null;
      }
      initialDate = candidate;
    }

    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: effectiveFirstDate,
      lastDate: effectiveLastDate,
      selectableDayPredicate: selectableDayPredicate,
    );
  }

  void _showNoSelectableDateMessage(BuildContext context) {
    SnackbarUtil.showInfo(context, 'No date is available to select for $label.');
  }

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: value,
      validator: validator,
      builder: (state) {
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: !enabled
              ? null
              : () async {
                  final picked = await _pickDate(context);
                  if (picked == null) return;
                  // Pass the freshly picked value directly - `value` (the
                  // widget field) won't reflect it until the parent rebuilds
                  // via onChanged, which happens on the next frame, not
                  // synchronously.
                  onChanged(picked);
                  state.didChange(picked);
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.calendar_today_outlined),
              enabled: enabled,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
              errorText: state.errorText,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
            child: Text(
              value != null
                  ? DateFormatter.format(value!)
                  : (enabled ? 'Select date' : disabledHintText),
              style: value == null
                  ? TextStyle(color: AppColors.textSecondaryFor(context))
                  : null,
            ),
          ),
        );
      },
    );
  }
}
