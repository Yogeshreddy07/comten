import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_dimensions.dart';
import 'pin_dots_indicator.dart';

/// A 4-digit PIN entry that looks like [PinDotsIndicator] rather than a
/// normal text field, while still using the system keyboard for input.
/// The actual [TextField] is fully transparent and zero-sized; tapping
/// anywhere on the dots focuses it. Input stays secure - the digits are
/// never rendered, only the filled/unfilled dot state is.
class PinCodeInput extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onCompleted;

  const PinCodeInput({
    super.key,
    required this.controller,
    this.length = 4,
    this.autofocus = false,
    this.onChanged,
    this.onCompleted,
  });

  @override
  State<PinCodeInput> createState() => _PinCodeInputState();
}

class _PinCodeInputState extends State<PinCodeInput> {
  final _focusNode = FocusNode();
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleChange);
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleChange() {
    setState(() {});
    widget.onChanged?.call(widget.controller.text);
    if (widget.controller.text.length == widget.length) {
      _focusNode.unfocus();
      widget.onCompleted?.call();
    }
  }

  void _handleFocusChange() {
    setState(() {});
  }

  void _toggleObscureText() {
    setState(() => _obscureText = !_obscureText);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // A Stack (rather than a Row splitting space between the dots and the
    // eye icon) so the dots are centered on the *full* available width -
    // otherwise the eye icon's width pulls the "centered" dots visibly off
    // from the actual center of the field.
    return SizedBox(
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: () {
              _focusNode.requestFocus();
              // Android Back hides the IME without dropping field focus.
              // requestFocus alone is then a no-op; reopen its connection.
              SystemChannels.textInput.invokeMethod<void>('TextInput.show');
            },
            behavior: HitTestBehavior.opaque,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PinDotsIndicator(
                  length: widget.length,
                  filledCount: widget.controller.text.length,
                  obscureText: _obscureText,
                  pin: widget.controller.text,
                  showCursor: _focusNode.hasFocus,
                ),
                Opacity(
                  opacity: 0,
                  alwaysIncludeSemantics: true,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      autofocus: widget.autofocus,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      showCursor: false,
                      maxLength: widget.length,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(counterText: ''),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            child: Padding(
              padding: EdgeInsets.only(left: AppDimensions.pinVisibilityIconSpacing),
              child: IconButton(
                onPressed: _toggleObscureText,
                icon: Icon(
                  _obscureText ? Icons.visibility_off : Icons.visibility,
                  color: colorScheme.outline,
                ),
                tooltip: _obscureText ? 'Show PIN' : 'Hide PIN',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
