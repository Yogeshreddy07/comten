import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/otp_input_row.dart';
import '../viewmodel/auth_viewmodel.dart';
import '../widgets/auth_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_text_field.dart';

enum ForgotPasswordStep {
  email,
  otp,
  resetPassword,
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _employeeCodeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpInputKey = GlobalKey<OtpInputRowState>();
  String _otp = '';

  ForgotPasswordStep _currentStep = ForgotPasswordStep.email;

  // Resend OTP handling
  Timer? _countdownTimer;
  int _secondsRemaining = 0;

  // The OTP step shows both "Verify OTP" and "Resend OTP" at once, and
  // both ultimately go through AuthViewModel.isLoading (Resend reuses
  // _sendOtp, which sets it too) - watching that shared flag directly for
  // Verify's spinner would make it light up whenever Resend is tapped.
  // This tracks only the verify action, for that spinner alone; the actual
  // tap-guard for both buttons still goes through viewModel.isLoading.
  bool _isVerifyingOtp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _employeeCodeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<AuthViewModel>(context);
    final isOtpStep = _currentStep == ForgotPasswordStep.otp;
    return PopScope(
      // On the OTP step, back doesn't exit the screen - it returns to the
      // email step (see _goBackToEmailStep) so a wrong/expired OTP doesn't
      // strand the user with no way out.
      canPop: !isOtpStep,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isOtpStep) _goBackToEmailStep();
      },
      child: AuthScaffold(
        title: 'Forgot Password',
        showBackButton: true,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              AuthHeader(
                icon: Icons.lock_reset,
                title: 'Forgot Password',
                subtitle: _currentStep == ForgotPasswordStep.otp
                    ? 'Enter the OTP sent to your registered email address.'
                    : 'Reset your password using your registered email address.',
              ),
              if (_currentStep == ForgotPasswordStep.email) _buildEmailStep(viewModel),
              if (_currentStep == ForgotPasswordStep.otp) _buildOtpStep(viewModel),
              if (_currentStep == ForgotPasswordStep.resetPassword) _buildResetPasswordStep(viewModel),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailStep(AuthViewModel viewModel) {
    return Column(
      children: [
        AuthTextField(
          controller: _employeeCodeController,
          label: 'Employee Code',
          icon: Icons.badge,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Employee code is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        AuthTextField(
          controller: _emailController,
          label: 'Company Email',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: Validators.email,
        ),
        const SizedBox(height: 30),
        AuthButton(
          text: 'Send OTP',
          isLoading: viewModel.isLoading,
          onPressed: viewModel.isLoading ? null : _sendOtp,
        ),
      ],
    );
  }

  Widget _buildOtpStep(AuthViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRegisteredEmailInfo(context),
        Text(
          'Enter OTP',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        OtpInputRow(
          key: _otpInputKey,
          length: 6,
          autofocus: true,
          onChanged: (code) => setState(() => _otp = code),
          onCompleted: viewModel.isLoading ? null : _verifyOtp,
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            _secondsRemaining > 0
                ? 'Resend OTP in ${_formatTime(_secondsRemaining)}'
                : "Didn't receive OTP?",
            style: TextStyle(color: AppColors.textSecondaryFor(context)),
          ),
        ),
        if (_secondsRemaining == 0)
          Center(
            child: TextButton(
              onPressed: viewModel.isLoading ? null : _resendOtp,
              child: const Text('Resend OTP'),
            ),
          ),
        const SizedBox(height: 24),
        AuthButton(
          text: 'Verify OTP',
          isLoading: _isVerifyingOtp,
          onPressed: viewModel.isLoading ? null : _verifyOtp,
        ),
      ],
    );
  }

  Widget _buildRegisteredEmailInfo(BuildContext context) {
    final masked = _maskEmail(_emailController.text.trim());
    if (masked.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.cardSpacing),
      child: Text(
        'Registered email: $masked',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondaryFor(context),
            ),
      ),
    );
  }

  /// Mirrors [_PhoneNumberScreenState._maskPhone]'s intent, adapted for an
  /// email: keep the first two local-part characters and the whole domain,
  /// star out the rest of the local part (e.g. "jo***@company.com").
  String _maskEmail(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 0) return email;
    final localPart = email.substring(0, atIndex);
    final domain = email.substring(atIndex);
    if (localPart.length <= 2) return '$localPart$domain';
    final visible = localPart.substring(0, 2);
    final stars = '*' * (localPart.length - 2);
    return '$visible$stars$domain';
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  Widget _buildResetPasswordStep(AuthViewModel viewModel) {
    return Column(
      children: [
        AuthTextField(
          controller: _newPasswordController,
          label: 'New Password',
          icon: Icons.lock_outline,
          isPassword: true,
          validator: Validators.password,
        ),
        const SizedBox(height: 20),
        AuthTextField(
          controller: _confirmPasswordController,
          label: 'Confirm Password',
          icon: Icons.lock_outline,
          isPassword: true,
          validator: (value) => Validators.confirmPassword(
            value,
            _newPasswordController.text,
          ),
        ),
        const SizedBox(height: 25),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Password Requirements",
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 10),
              const Text("• Minimum 8 characters"),
              const Text("• Use uppercase & lowercase letters"),
              const Text("• Include at least one number"),
              const Text("• Include one special character"),
            ],
          ),
        ),
        const SizedBox(height: 30),
        AuthButton(
          text: 'Reset Password',
          isLoading: viewModel.isLoading,
          onPressed: viewModel.isLoading ? null : _resetPassword,
        ),
      ],
    );
  }

  /// Returns from the OTP step to the email step (see [PopScope] above),
  /// instead of exiting the screen - lets the user correct the email/employee
  /// code or simply back out after a wrong/expired OTP.
  void _goBackToEmailStep() {
    _countdownTimer?.cancel();
    setState(() {
      _secondsRemaining = 0;
      _otp = '';
      _currentStep = ForgotPasswordStep.email;
    });
  }

  Future<void> _startResendTimer(int seconds) async {
    setState(() {
      _secondsRemaining = seconds;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
        });
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  Future<void> _sendOtp() async {
    final viewModel = context.read<AuthViewModel>();
    if (viewModel.isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    final empCode = _employeeCodeController.text.trim().isNotEmpty
        ? _employeeCodeController.text.trim()
        : viewModel.employeeCode;
    final result = await viewModel.sendForgotPasswordOtp(
      employeeCode: empCode,
      email: _emailController.text.trim(),
    );
    if (!mounted) return;
    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);
      setState(() {
        _currentStep = ForgotPasswordStep.otp;
      });
      await _startResendTimer(60);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  Future<void> _resendOtp() async {
    // Reuse send OTP logic; backend will enforce cooldown.
    await _sendOtp();
  }

  Future<void> _verifyOtp() async {
    final viewModel = context.read<AuthViewModel>();
    if (viewModel.isLoading) return;

    if (_otp.length != 6) {
      SnackbarUtil.showError(context, 'Enter the complete 6-digit OTP');
      return;
    }
    setState(() => _isVerifyingOtp = true);
    final empCode = _employeeCodeController.text.trim().isNotEmpty
        ? _employeeCodeController.text.trim()
        : viewModel.employeeCode;
    final result = await viewModel.verifyForgotPasswordOtp(
      employeeCode: empCode,
      email: _emailController.text.trim(),
      otp: _otp,
    );
    if (!mounted) return;
    setState(() => _isVerifyingOtp = false);
    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);
      setState(() {
        _currentStep = ForgotPasswordStep.resetPassword;
      });
    } else {
      SnackbarUtil.showError(context, result.message);
      _otpInputKey.currentState?.clear();
    }
  }

  Future<void> _resetPassword() async {
    final viewModel = context.read<AuthViewModel>();
    if (viewModel.isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final empCode = _employeeCodeController.text.trim().isNotEmpty
        ? _employeeCodeController.text.trim()
        : viewModel.employeeCode;
    final result = await viewModel.resetForgotPassword(
      employeeCode: empCode,
      newPassword: _newPasswordController.text.trim(),
      confirmPassword: _confirmPasswordController.text.trim(),
    );
    if (!mounted) return;
    if (result.success) {
      SnackbarUtil.showSuccessOn(messenger, result.message);
      Navigator.pop(context);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }
}