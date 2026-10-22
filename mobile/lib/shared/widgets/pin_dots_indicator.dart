import 'package:flutter/material.dart';

import '../constants/app_dimensions.dart';

/// Filled/unfilled dot row used to represent PIN entry progress, matching
/// common banking/payment app PIN UIs. Purely presentational - drive
/// [filledCount] from whatever is capturing the digits (a hidden text field
/// via [PinCodeInput], or a custom keypad).
///
/// When [obscureText] is false, filled slots render the actual digit from
/// [pin] instead of a plain dot - the same visibility-toggle pattern used by
/// password fields. Visible digits are drawn as plain, unboxed text (no fill,
/// no border) so revealed digits read cleanly, while each slot keeps the
/// exact width/spacing of the dot layout so nothing shifts on toggle.
///
/// When [showCursor] is true, the next still-empty slot (the one the next
/// keystroke will fill) shows a small blinking caret instead of its plain
/// outline, the same way a real text field shows where typing will land -
/// purely visual, driven entirely by the caller (e.g. [PinCodeInput] passing
/// its `FocusNode`'s focus state); it has no effect on input handling.
class PinDotsIndicator extends StatefulWidget {
  final int length;
  final int filledCount;
  final bool obscureText;
  final String pin;
  final bool showCursor;

  const PinDotsIndicator({
    super.key,
    required this.length,
    required this.filledCount,
    this.obscureText = true,
    this.pin = '',
    this.showCursor = false,
  });

  @override
  State<PinDotsIndicator> createState() => _PinDotsIndicatorState();
}

class _PinDotsIndicatorState extends State<PinDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (index) {
        final isFilled = index < widget.filledCount;
        final showDigit =
            !widget.obscureText && isFilled && index < widget.pin.length;
        final isCursorSlot =
            widget.showCursor && !isFilled && index == widget.filledCount;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          margin: EdgeInsets.symmetric(horizontal: AppDimensions.pinDotSpacing / 2),
          width: AppDimensions.pinDotSize,
          height: AppDimensions.pinDotSize,
          decoration: showDigit
              ? null
              : BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled ? colorScheme.primary : Colors.transparent,
                  border: Border.all(
                    color: isFilled ? colorScheme.primary : colorScheme.outline,
                    width: 1.5,
                  ),
                ),
          child: showDigit
              ? Text(
                  widget.pin[index],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                )
              : (isCursorSlot ? _buildCursor(colorScheme) : null),
        );
      }),
    );
  }

  Widget _buildCursor(ColorScheme colorScheme) {
    return FadeTransition(
      opacity: _cursorController,
      child: Container(
        width: 2,
        height: AppDimensions.pinDotSize * 0.55,
        decoration: BoxDecoration(
          color: colorScheme.primary,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
