import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../dashboard/utils/role_dashboard_navigator.dart';
import '../viewmodel/auth_viewmodel.dart';
import '../widgets/auth_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_text_field.dart';
import 'forgot_password_screen.dart';
import 'activate_account_screen.dart';
import 'create_pin_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _employeeCodeController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _employeeCodeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final viewModel = context.read<AuthViewModel>();

    if (viewModel.isLoading) {
      return;
    }

    final employeeCode = _employeeCodeController.text.trim();
    final result = await viewModel.login(
      employeeCode: employeeCode,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(
        context,
        result.message,
      );

      final data = result.data;
      if (data != null) {
        final bool phoneVerified = data['phoneVerified'] ?? false;
        final String empCode = data['employeeCode'] ?? employeeCode;

        if (!phoneVerified && data['emailVerified'] != true) {
          if (!context.canPushRoute) return;
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const ActivateAccountScreen(),
            ),
          );
          return;
        }

        // App lock (PIN + fingerprint) is device-level, not per-account - if
        // this device already has one configured (by this account or any
        // other that signed in on it), skip straight to the dashboard.
        final hasAppLock = await viewModel.hasAppLockConfigured();
        if (!mounted) return;

        if (hasAppLock) {
          await viewModel.saveOnboardingCompleted(empCode, true);
          if (!mounted) return;
          await RoleDashboardNavigator.navigate(context, viewModel.role);
        } else {
          if (!context.canPushRoute) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreatePinScreen(employeeCode: empCode),
            ),
          );
        }
      }
    } else {
      SnackbarUtil.showError(
        context,
        result.message,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AuthViewModel>();
    final isLoading = viewModel.isLoading;

    return AuthScaffold(
      title: "Login",
      showBackButton: false,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),

            const AuthHeader(
              icon: Icons.lock_outline,
              title: "Welcome Back",
              subtitle: "Login using your employee credentials.",
            ),

            AuthTextField(
              controller: _employeeCodeController,
              label: "Employee Code",
              icon: Icons.badge_outlined,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Employee Code is required";
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            AuthTextField(
              controller: _passwordController,
              label: "Password",
              icon: Icons.lock_outline,
              isPassword: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return "Password is required";
                }
                return null;
              },
            ),

            const SizedBox(height: 10),

            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  if (!context.canPushRoute) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen(),
                    ),
                  );
                },
                child: const Text("Forgot Password?"),
              ),
            ),

            const SizedBox(height: 15),

            AuthButton(
              text: "Login",
              isLoading: isLoading,
              onPressed: isLoading ? null : _login,
            ),
          ],
        ),
      ),
    );
  }
}
