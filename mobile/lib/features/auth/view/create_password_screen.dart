import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_card.dart';
import '../viewmodel/auth_viewmodel.dart';
import '../widgets/auth_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_text_field.dart';
import 'phonenumber_verification_screen.dart';

class CreatePasswordScreen extends StatefulWidget {
  final String employeeCode;

  const CreatePasswordScreen({
    super.key,
    required this.employeeCode,
  });

  @override
  State<CreatePasswordScreen> createState() =>
      _CreatePasswordScreenState();
}

class _CreatePasswordScreenState
    extends State<CreatePasswordScreen> {

  final _formKey = GlobalKey<FormState>();

  final _passwordController =
  TextEditingController();

  final _confirmPasswordController =
  TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final viewModel =
    context.read<AuthViewModel>();

    if (viewModel.isLoading) return;

    final result = await viewModel.setPassword(
      newPassword: _passwordController.text.trim(),
      confirmPassword: _confirmPasswordController.text.trim(),
    );

    if (!mounted) return;

    if (result.success) {

      SnackbarUtil.showSuccess(
        context,
        result.message,
      );

      if (!context.canPushRoute) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PhoneNumberScreen(
                employeeCode:
                widget.employeeCode,
              ),
        ),
      );

    } else {

      SnackbarUtil.showError(
        context,
        result.message,
      );

    }
  }

  @override
  Widget build(BuildContext context) {

    final viewModel =
    context.watch<AuthViewModel>();

    // Activation is a strictly forward flow - going back here would return to
    // Activate Account with the signup token already partially spent (see
    // AuthServiceImpl#setPassword), so back navigation is disabled entirely
    // rather than just hiding the AppBar icon.
    return PopScope(
      canPop: false,
      child: AuthScaffold(
      title: "Create Password",
      showBackButton: false,

      child: Form(
        key: _formKey,

        child: Column(
          children: [

            const SizedBox(height: 20),

            const AuthHeader(
              icon: Icons.lock_reset,
              title: "Create Password",
              subtitle:
              "Create a secure password for your account.",
            ),

            const SizedBox(height: 30),

            AuthTextField(
              controller:
              _passwordController,
              label: "New Password",
              icon: Icons.lock_outline,
              isPassword: true,
              validator:
              Validators.password,
            ),

            const SizedBox(height: 20),

            AuthTextField(
              controller:
              _confirmPasswordController,
              label: "Confirm Password",
              icon: Icons.lock_outline,
              isPassword: true,
              validator: (value) =>
                  Validators.confirmPassword(
                    value,
                    _passwordController.text,
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
              text: "Continue",
              isLoading:
              viewModel.isLoading,
              onPressed: viewModel.isLoading ? null : _continue,
            ),
          ],
        ),
      ),
      ),
    );
  }
}