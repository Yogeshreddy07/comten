class Validators {
  Validators._();

  static String? requiredField(
      String? value,
      String fieldName,
      ) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    final trimmed = value.trim();

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?'
      r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }

    // On top of the general shape check above (requires "@", a valid local
    // part, and a valid domain), only ".com" addresses are accepted - checked
    // separately so a non-.com address gets its own explanatory message
    // instead of being lumped in with "not a valid email at all".
    if (!trimmed.toLowerCase().endsWith('.com')) {
      return 'Only .com email addresses are allowed';
    }

    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Missing uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Missing lowercase letter';
    }
    if (!RegExp(r'\d').hasMatch(value)) {
      return 'Missing number';
    }
    if (!RegExp(r'[@$!%*?&]').hasMatch(value)) {
      return 'Please include at least one special character in your password.';
    }
    if (value.length < 8) {
      return 'Minimum 8 characters required';
    }

    return null;
  }

  static String? confirmPassword(
      String? value,
      String password,
      ) {
    if (value == null || value.isEmpty) {
      return 'Confirm Password is required';
    }

    if (value != password) {
      return 'Passwords do not match';
    }

    return null;
  }

  static String? employeeCode(String? value) {
    return requiredField(
      value,
      'Employee Code',
    );
  }

  static String? temporaryPassword(
      String? value,
      ) {
    return requiredField(
      value,
      'Temporary Password',
    );
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone Number is required';
    }

    if (!RegExp(r'^[0-9]{10}$').hasMatch(value.trim())) {
      return 'Enter a valid 10-digit phone number';
    }

    return null;
  }

  static String? otp(
      String? value, {
        int length = 6,
      }) {
    if (value == null || value.trim().isEmpty) {
      return 'OTP is required';
    }

    if (value.trim().length != length) {
      return 'OTP must be $length digits';
    }

    return null;
  }

  static String? pin(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'PIN is required';
    }

    if (!RegExp(r'^[0-9]{4}$').hasMatch(value.trim())) {
      return 'PIN must be exactly 4 digits';
    }

    return null;
  }

  static String? confirmPin(
      String? value,
      String pin,
      ) {
    if (value == null || value.trim().isEmpty) {
      return 'Confirm PIN is required';
    }

    if (value != pin) {
      return 'PIN does not match';
    }

    return null;
  }
}