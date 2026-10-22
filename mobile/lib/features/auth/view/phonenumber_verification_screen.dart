import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/phone_verification_channel.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/widgets/otp_input_row.dart';
import '../../dashboard/utils/role_dashboard_navigator.dart';
import '../viewmodel/auth_viewmodel.dart';
import '../widgets/auth_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import 'create_pin_screen.dart';

class PhoneNumberScreen extends StatefulWidget {
  final String employeeCode;

  const PhoneNumberScreen({super.key, required this.employeeCode});

  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  late AuthViewModel _viewModel;
  StreamSubscription<PhoneVerificationEvent>? _eventSubscription;

  final _phoneInputKey = GlobalKey<OtpInputRowState>();
  String _phoneDigits = '';

  bool _isLoadingPhone = true;
  String _errorMessage = '';
  String _maskedPhone = '';

  bool _codeSent = false;
  bool _isSending = false; // prevents duplicate "send code" taps
  bool _isVerifying = false;

  String? _verificationId;
  final _otpInputKey = GlobalKey<OtpInputRowState>();
  String _otpCode = '';

  Timer? _timer;
  int _remainingSeconds = 120;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<AuthViewModel>();
    _fetchPhoneNumber();
    _eventSubscription = _viewModel.phoneVerificationEvents.listen(
      _handleEvent,
    );
  }

  Future<void> _fetchPhoneNumber() async {
    setState(() {
      _isLoadingPhone = true;
      _errorMessage = '';
    });
    try {
      final result = await _viewModel.fetchPhoneNumber(widget.employeeCode);
      if (!mounted) return;
      if (result.success) {
        final phone = _viewModel.phoneNumber ?? '';
        setState(() {
          _maskedPhone = _maskPhone(phone);
        });
      } else {
        setState(() {
          _errorMessage = result.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Failed to fetch phone number. Please try again.";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPhone = false;
        });
      }
    }
  }

  String _maskPhone(String phone) {
    if (phone.isEmpty) return "No phone number found";
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.length < 2) return cleanPhone;
    final lastTwo = cleanPhone.substring(cleanPhone.length - 2);
    final stars = '*' * (cleanPhone.length - 2);
    return "$stars$lastTwo";
  }

  /// Firebase requires E.164 - the user-entered digits are always a plain 10-digit number
  /// (see [_phoneDigits]), same assumption [AuthRepository._formatPhone] already makes for
  /// the equivalent backend call.
  String _formattedPhone() => '+91$_phoneDigits';

  /// Whether [_phoneDigits] matches the number on file for this employee (see
  /// [AuthViewModel.phoneNumber], populated by [_fetchPhoneNumber]). Compared on the last 10
  /// digits since the registered number may or may not carry a country-code prefix.
  bool _matchesRegisteredNumber() {
    final registered = (_viewModel.phoneNumber ?? '').replaceAll(
      RegExp(r'\D'),
      '',
    );
    if (registered.isEmpty) {
      return true; // nothing to compare against - let the backend decide
    }
    final registeredLastTen = registered.length > 10
        ? registered.substring(registered.length - 10)
        : registered;
    return _phoneDigits == registeredLastTen;
  }

  void _handleEvent(PhoneVerificationEvent event) {
    if (!mounted) return;
    switch (event) {
      case PhoneCodeSent(:final verificationId):
        setState(() {
          _isSending = false;
          _codeSent = true;
          _verificationId = verificationId;
        });
        _startTimer();
        SnackbarUtil.showInfo(context, "Verification code sent");
      case PhoneAutoVerified(:final idToken):
        _completeVerification(idToken: idToken);
      case PhoneVerificationFailed(:final message):
        setState(() {
          _isSending = false;
          _isVerifying = false;
        });
        SnackbarUtil.showError(context, message);
    }
  }

  Future<void> _sendCode() async {
    if (_isSending) return; // guard against double tap

    if (_phoneDigits.length != 10) {
      SnackbarUtil.showError(context, "Enter your 10-digit phone number");
      return;
    }

    // Checked against the registered number on file before ever calling Firebase - a mismatch
    // here would otherwise only surface after Firebase has already sent a real SMS and the
    // backend's own equality check (AuthServiceImpl.verifyPhoneToken) rejects it at the final
    // verify step.
    if (!_matchesRegisteredNumber()) {
      SnackbarUtil.showError(
        context,
        "This number doesn't match the one on file for your account.",
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await _viewModel.startPhoneVerification(_formattedPhone());
      // Result (codeSent/autoVerified/failed) arrives via _handleEvent.
    } catch (e) {
      if (!mounted) return;
      // Surfaced to the user only as a generic message below - logged here so the real cause
      // (Firebase/Play Integrity error, missing platform channel, etc.) is visible when running
      // via `flutter run` instead of being swallowed entirely.
      debugPrint("startPhoneVerification failed: $e");
      setState(() {
        _isSending = false;
      });
      SnackbarUtil.showError(
        context,
        "Failed to send verification code. Please try again.",
      );
    }
  }

  void _startTimer() {
    _remainingSeconds = 120;
    _canResend = false;

    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds == 0) {
        setState(() {
          _canResend = true;
        });
        timer.cancel();
      } else {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  Future<void> _resendCode() async {
    if (!_canResend || _isSending) return;
    _otpInputKey.currentState?.clear();

    setState(() {
      _isSending = true;
    });

    try {
      await _viewModel.resendPhoneVerificationCode(_formattedPhone());
    } catch (e) {
      if (!mounted) return;
      debugPrint("resendPhoneVerificationCode failed: $e");
      setState(() {
        _isSending = false;
      });
      SnackbarUtil.showError(
        context,
        "Failed to resend verification code. Please try again.",
      );
    }
  }

  Future<void> _verifyCode() async {
    if (_otpCode.length != 6) {
      SnackbarUtil.showError(context, "Enter complete code");
      return;
    }
    final verificationId = _verificationId;
    if (verificationId == null) return;
    await _completeVerification(verificationId: verificationId, code: _otpCode);
  }

  Future<void> _completeVerification({
    String? verificationId,
    String? code,
    String? idToken,
  }) async {
    if (_isVerifying) return; // guard against double tap

    setState(() {
      _isVerifying = true;
    });
    try {
      final result = await _viewModel.confirmPhoneVerification(
        verificationId: verificationId,
        code: code,
        idToken: idToken,
      );

      if (!mounted) return;

      if (result.success) {
        SnackbarUtil.showSuccess(context, "Phone number verified successfully");

        // Left true rather than reset here - this screen is about to be
        // navigated away from entirely, so re-enabling the button for the
        // moment before that happens would only reopen the same race a
        // rapid second tap exploited.
        //
        // App lock (PIN + fingerprint) is device-level, not per-account - if
        // this device already has one configured, skip straight to the
        // dashboard instead of prompting for it again.
        final hasAppLock = await _viewModel.hasAppLockConfigured();
        if (!mounted) return;

        if (hasAppLock) {
          await _viewModel.saveOnboardingCompleted(widget.employeeCode, true);
          if (!mounted) return;
          await RoleDashboardNavigator.navigate(context, _viewModel.role);
        } else {
          if (!context.canPushRoute) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CreatePinScreen(employeeCode: widget.employeeCode),
            ),
          );
        }
      } else {
        setState(() {
          _isVerifying = false;
        });
        SnackbarUtil.showError(context, result.message);
        _otpInputKey.currentState?.clear();
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint("confirmPhoneVerification failed: $e");
      setState(() {
        _isVerifying = false;
      });
      SnackbarUtil.showError(
        context,
        "Connection error: Please check if the backend server is running.",
      );
    }
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  @override
  void dispose() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _eventSubscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  Widget _buildRegisteredPhoneInfo(BuildContext context) {
    if (_isLoadingPhone) {
      // No loading indicator while the registered number is being fetched -
      // the phone input/error text below just appears once it resolves.
      return const SizedBox.shrink();
    }

    if (_errorMessage.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppDimensions.cardSpacing),
        child: Column(
          children: [
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            TextButton(
              onPressed: _fetchPhoneNumber,
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    if (_maskedPhone.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.cardSpacing),
      child: Text(
        "Registered number: $_maskedPhone",
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondaryFor(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Mandatory onboarding step (activation or first-run phone verification) -
    // going back would strand the user mid-verification with no useful prior
    // screen to return to, so back navigation is disabled entirely.
    return PopScope(
      canPop: false,
      child: AuthScaffold(
        title: "Verify Phone",
        showBackButton: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),

            AuthHeader(
              icon: Icons.sms_outlined,
              title: "Verify Your Phone Number",
              subtitle: _codeSent
                  ? "Enter the 6-digit code sent to your phone."
                  : "Enter the 10-digit mobile number associated with your employee account.",
            ),

            _buildRegisteredPhoneInfo(context),

            IgnorePointer(
              ignoring: _codeSent,
              child: Opacity(
                opacity: _codeSent ? 0.6 : 1,
                child: OtpInputRow(
                  key: _phoneInputKey,
                  length: 10,
                  autofocus: true,
                  enableOtpAutofill: false,
                  onChanged: (digits) => setState(() => _phoneDigits = digits),
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (!_codeSent)
              AuthButton(
                text: "Send Code",
                isLoading: _isSending,
                onPressed: _isSending ? null : _sendCode,
              ),

            if (_codeSent) ...[
              OtpInputRow(
                key: _otpInputKey,
                length: 6,
                autofocus: true,
                onChanged: (code) => setState(() => _otpCode = code),
                onCompleted: _isVerifying ? null : _verifyCode,
              ),

              const SizedBox(height: 20),

              Center(
                child: Text(
                  _canResend
                      ? "Didn't receive the code?"
                      : "Resend code in ${_formatTime(_remainingSeconds)}",
                  style: TextStyle(color: AppColors.textSecondaryFor(context)),
                ),
              ),

              if (_canResend)
                Center(
                  child: TextButton(
                    onPressed: _isSending ? null : _resendCode,
                    child: const Text("Resend Code"),
                  ),
                ),

              const SizedBox(height: 24),

              AuthButton(
                text: "Verify Code",
                isLoading: _isVerifying,
                onPressed: _isVerifying ? null : _verifyCode,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
