import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_card.dart';
import '../../auth/view/forgot_password_screen.dart';
import '../../auth/widgets/auth_button.dart';
import '../../auth/widgets/auth_header.dart';
import '../../auth/widgets/auth_scaffold.dart';
import '../../auth/widgets/auth_text_field.dart';
import '../viewmodel/settings_view_model.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final viewModel = context.read<SettingsViewModel>();
    if (viewModel.isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    final result = await viewModel.changePassword(
      currentPassword: _currentPasswordController.text.trim(),
      newPassword: _newPasswordController.text.trim(),
      confirmPassword: _confirmPasswordController.text.trim(),
    );

    if (!mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, AppStrings.changePasswordSuccess);
      Navigator.pop(context);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<SettingsViewModel>();

    return AuthScaffold(
      title: AppStrings.changePasswordTitle,
      showThemeToggle: false,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const SizedBox(height: 20),
            const AuthHeader(
              icon: Icons.lock_reset,
              title: AppStrings.changePasswordTitle,
              subtitle: "Update your account password to keep it secure.",
            ),
            const SizedBox(height: 10),
            AuthTextField(
              controller: _currentPasswordController,
              label: AppStrings.changePasswordCurrentLabel,
              icon: Icons.lock_outline,
              isPassword: true,
              validator: (value) =>
                  Validators.requiredField(value, "Current Password"),
            ),
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
                child: const Text("Forgot current password?"),
              ),
            ),
            AuthTextField(
              controller: _newPasswordController,
              label: AppStrings.changePasswordNewLabel,
              icon: Icons.lock_outline,
              isPassword: true,
              validator: Validators.password,
            ),
            const SizedBox(height: 20),
            AuthTextField(
              controller: _confirmPasswordController,
              label: AppStrings.changePasswordConfirmLabel,
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
              text: AppStrings.changePasswordButton,
              isLoading: viewModel.isSaving,
              onPressed: viewModel.isSaving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
