import 'package:flutter/services.dart';

class UppercaseTextInputFormatter extends TextInputFormatter {
  const UppercaseTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
