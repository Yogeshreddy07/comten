import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_dimensions.dart';

/// A row of individual OTP digit boxes that correctly handles pasting the
/// full code (long-press paste, keyboard clipboard suggestions, Android's
/// "Copy OTP" suggestion, and SMS autofill where the platform supports it)
/// in addition to normal one-digit-at-a-time typing and backspacing.
///
/// Previously each box used a [LengthLimitingTextInputFormatter(1)], which
/// silently discarded every digit but the first when a full code was pasted.
/// This widget instead lets the full pasted value reach [onChanged] and
/// distributes it across all boxes.
class OtpInputRow extends StatefulWidget {
  final int length;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCompleted;
  final bool autofocus;

  /// Whether the first box advertises itself to the platform as a one-time-code field
  /// (enables SMS autofill / "Copy OTP" suggestions). Only meaningful for actual OTP entry -
  /// off by default reuse of this widget for other fixed-length digit entry (e.g. a phone
  /// number) would otherwise wrongly prompt the OS to autofill an OTP into it.
  final bool enableOtpAutofill;

  const OtpInputRow({
    super.key,
    this.length = 6,
    required this.onChanged,
    this.onCompleted,
    this.autofocus = false,
    this.enableOtpAutofill = true,
  });

  @override
  State<OtpInputRow> createState() => OtpInputRowState();
}

class OtpInputRowState extends State<OtpInputRow> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (index) {
      final node = FocusNode(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            _handleBackspace(index);
          }
          return KeyEventResult.ignored;
        },
      );
      // Selects any existing digit when a box gains focus so typing over it
      // replaces the digit instead of appending to it (which would otherwise
      // create a 2-character value and be misdetected as a paste).
      node.addListener(() {
        if (node.hasFocus) {
          _controllers[index].selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controllers[index].text.length,
          );
        }
      });
      return node;
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  /// Clears every box and refocuses the first one - used when resending.
  void clear() {
    for (final controller in _controllers) {
      controller.clear();
    }
    setState(() {});
    _focusNodes[0].requestFocus();
    widget.onChanged('');
  }

  void _handlePaste(String pasted) {
    final digits = pasted.replaceAll(RegExp(r'[^0-9]'), '');

    for (var i = 0; i < widget.length; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }

    final lastFilledIndex = digits.length.clamp(0, widget.length) - 1;
    if (lastFilledIndex >= 0) {
      _focusNodes[lastFilledIndex].requestFocus();
    }

    setState(() {});
    widget.onChanged(_code);
    if (_code.length == widget.length) {
      FocusScope.of(context).unfocus();
      widget.onCompleted?.call();
    }
  }

  void _handleChanged(String value, int index) {
    // A value longer than one character can only arrive via paste, keyboard
    // clipboard suggestions, "Copy OTP", or SMS autofill - never from normal
    // single-key typing - so it's handled as a full-code paste.
    if (value.length > 1) {
      _handlePaste(value);
      return;
    }

    if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    setState(() {});
    widget.onChanged(_code);
    if (_code.length == widget.length) {
      FocusScope.of(context).unfocus();
      widget.onCompleted?.call();
    }
  }

  /// Handles backspace on a box that is already empty (deleting its own
  /// digit is handled by [_handleChanged] instead) by moving focus back to
  /// the previous box, mirroring standard OTP field navigation.
  void _handleBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppDimensions.inputRadius);

    // Each box is capped at otpBoxWidth (so a short code like a 6-digit OTP
    // looks the same as before) but flexes down to fit the row when `length`
    // boxes at that width wouldn't otherwise fit (e.g. a 10-digit phone
    // number on a narrow screen) - a fixed-width SizedBox per box would just
    // overflow the row instead of shrinking.
    return AutofillGroup(
      child: Row(
        children: List.generate(widget.length, (index) {
          final field = TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            autofocus: widget.autofocus && index == 0,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            autofillHints: (widget.enableOtpAutofill && index == 0)
                ? const [AutofillHints.oneTimeCode]
                : null,
            style: Theme.of(context).textTheme.headlineSmall,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
            ),
            onChanged: (value) => _handleChanged(value, index),
          );

          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == widget.length - 1
                    ? 0
                    : AppDimensions.otpBoxSpacing,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppDimensions.otpBoxWidth,
                  ),
                  child: field,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
