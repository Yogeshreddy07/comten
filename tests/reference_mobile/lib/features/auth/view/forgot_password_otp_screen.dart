import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/snackbar_util.dart';
import '../../../shared/widgets/otp_input_row.dart';
import '../viewmodel/auth_viewmodel.dart';
import '../widgets/auth_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import 'reset_password_screen.dart';

class ForgotPasswordOtpScreen extends StatefulWidget {
  final String email;

  const ForgotPasswordOtpScreen({
    super.key,
    required this.email,
  });

  @override
  State<ForgotPasswordOtpScreen> createState() =>
      _ForgotPasswordOtpScreenState();
}

class _ForgotPasswordOtpScreenState extends State<ForgotPasswordOtpScreen> {
  late AuthViewModel _viewModel;
  String _otp = '';

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<AuthViewModel>();
  }

  Future<void> _verifyOtp() async {
    if (_otp.length != 6) {
      SnackbarUtil.showError(context, "Enter the complete 6-digit OTP");
      return;
    }

    final result = await _viewModel.verifyForgotPasswordOtp(
      employeeCode: _viewModel.employeeCode,
      email: widget.email,
      otp: _otp,
    );

    if (!mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
      );
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AuthViewModel>();

    return AuthScaffold(
      title: "Verify OTP",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),

          const AuthHeader(
            icon: Icons.security,
            title: "Verify OTP",
            subtitle: "Enter the OTP sent to your email address.",
          ),

          OtpInputRow(
            length: 6,
            autofocus: true,
            onChanged: (code) => setState(() => _otp = code),
            onCompleted: viewModel.isLoading ? null : _verifyOtp,
          ),

          const SizedBox(height: 30),

          AuthButton(
            text: "Verify OTP",
            isLoading: viewModel.isLoading,
            onPressed: viewModel.isLoading ? null : _verifyOtp,
          ),

          const SizedBox(height: 16),

          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Back"),
            ),
          ),
        ],
      ),
    );
  }
}
