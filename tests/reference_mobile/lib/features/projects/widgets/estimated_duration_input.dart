import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';

/// Three unbounded-length numeric boxes (Hours : Minutes : Seconds) that
/// behave as a single time-input component. No digit-count limit is
/// applied on any box - large hour totals (120, 1000, ...) are valid.
class EstimatedDurationInput extends StatelessWidget {
  final String label;
  final TextEditingController hoursController;
  final TextEditingController minutesController;
  final TextEditingController secondsController;
  final String? errorText;

  const EstimatedDurationInput({
    super.key,
    required this.label,
    required this.hoursController,
    required this.minutesController,
    required this.secondsController,
    this.errorText,
  });

  /// Shared "H:M:S" -> display text formatting, so Review/Success screens
  /// render the exact same format the input uses.
  static String formatDisplay(String hoursText, String minutesText, String secondsText) {
    final hours = int.tryParse(hoursText.trim()) ?? 0;
    final minutes = int.tryParse(minutesText.trim()) ?? 0;
    final seconds = int.tryParse(secondsText.trim()) ?? 0;
    return '${hours}h ${minutes}m ${seconds}s';
  }

  Widget _box(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const separator = Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.textSecondaryFor(context), fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _box(hoursController, AppStrings.estimatedDurationHoursHint),
            ),
            separator,
            Expanded(
              child:
                  _box(minutesController, AppStrings.estimatedDurationMinutesHint),
            ),
            separator,
            Expanded(
              child:
                  _box(secondsController, AppStrings.estimatedDurationSecondsHint),
            ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              errorText!,
              style: TextStyle(color: colorScheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
