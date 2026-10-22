import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../core/utils/validators.dart';
import '../viewmodel/auth_viewmodel.dart';
import '../widgets/auth_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_text_field.dart';
import 'create_password_screen.dart';

class ActivateAccountScreen extends StatefulWidget {
  const ActivateAccountScreen({super.key});

  @override
  State<ActivateAccountScreen> createState() =>
      _ActivateAccountScreenState();
}

class _ActivateAccountScreenState
    extends State<ActivateAccountScreen> {
  final _formKey = GlobalKey<FormState>();

  final _employeeCodeController =
  TextEditingController();

  final _temporaryPasswordController =
  TextEditingController();

  @override
  void dispose() {
    _employeeCodeController.dispose();
    _temporaryPasswordController.dispose();
    super.dispose();
  }

  Future<void> _activateAccount() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final viewModel =
    context.read<AuthViewModel>();

    if (viewModel.isLoading) return;

    final result =
    await viewModel.verifyTempPassword(
      employeeCode:
      _employeeCodeController.text.trim(),
      tempPassword:
      _temporaryPasswordController.text.trim(),
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
              CreatePasswordScreen(
                employeeCode:
                _employeeCodeController.text
                    .trim(),
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

    return AuthScaffold(
      title: "Activate Account",
      child: Form(
        key: _formKey,
        child: Column(
          children: [

            const SizedBox(height: 20),

            const AuthHeader(
              icon: Icons.verified_user_outlined,
              title: "Activate Account",
              subtitle:
              "Enter the Employee Code and Temporary Password sent to your company email.",
            ),

            const SizedBox(height: 30),

            AuthTextField(
              controller:
              _employeeCodeController,
              label: "Employee Code",
              icon: Icons.badge_outlined,
              validator:
              Validators.employeeCode,
            ),

            const SizedBox(height: 20),

            AuthTextField(
              controller:
              _temporaryPasswordController,
              label: "Temporary Password",
              icon: Icons.lock_outline,
              isPassword: true,
              validator:
              Validators.temporaryPassword,
            ),

            const SizedBox(height: 25),

            Builder(
              builder: (context) {
                final colorScheme = Theme.of(context).colorScheme;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Use the temporary password received in your registered company email. After successful verification, you'll be asked to create your own password.",
                          style: TextStyle(color: colorScheme.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 30),

            AuthButton(
              text: "Continue",
              isLoading:
              viewModel.isLoading,
              onPressed:
              viewModel.isLoading ? null : _activateAccount,
            ),
          ],
        ),
      ),
    );
  }
}