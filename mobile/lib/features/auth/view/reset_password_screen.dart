import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/snackbar_util.dart';
import 'login_screen.dart';
import '../viewmodel/auth_viewmodel.dart';
import '../widgets/auth_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_text_field.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_card.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late AuthViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<AuthViewModel>();
  }

  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final password = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    final validation = Validators.password(password);
    if (validation != null) {
      SnackbarUtil.showError(context, validation);
      return;
    }

    if (password != confirmPassword) {
      SnackbarUtil.showError(context, "Passwords do not match");
      return;
    }

    final result = await _viewModel.resetForgotPassword(
      employeeCode: _viewModel.employeeCode,
      newPassword: password,
      confirmPassword: confirmPassword,
    );

    if (!mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: "Reset Password",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),

          const AuthHeader(
            icon: Icons.lock_reset,
            title: "Reset Password",
            subtitle: "Create a new password for your account.",
          ),

          AuthTextField(
            controller: _newPasswordController,
            label: "New Password",
            icon: Icons.lock_outline,
            isPassword: true,
          ),

          const SizedBox(height: 20),

          AuthTextField(
            controller: _confirmPasswordController,
            label: "Confirm Password",
            icon: Icons.lock_outline,
            isPassword: true,
          ),

          const SizedBox(height: 24),

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
                const Text("• One uppercase letter"),
                const Text("• One lowercase letter"),
                const Text("• One number"),
                const Text("• One special character"),
              ],
            ),
          ),

          const SizedBox(height: 30),

          Consumer<AuthViewModel>(
            builder: (context, viewModel, _) => AuthButton(
              text: "Reset Password",
              isLoading: viewModel.isLoading,
              onPressed: viewModel.isLoading ? null : _resetPassword,
            ),
          ),
        ],
      ),
    );
  }
}
