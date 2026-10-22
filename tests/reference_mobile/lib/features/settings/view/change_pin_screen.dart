import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/pin_code_input.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../../auth/widgets/auth_button.dart';
import '../../auth/widgets/auth_header.dart';
import '../../auth/widgets/auth_scaffold.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newPin = _newPinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (newPin.length != 4 || confirmPin.length != 4) {
      SnackbarUtil.showError(context, "PIN must be exactly 4 digits");
      return;
    }
    if (newPin != confirmPin) {
      SnackbarUtil.showError(context, "PIN does not match");
      return;
    }

    setState(() => _isSaving = true);

    // Device-level app lock PIN - stored locally only, shared by every
    // account signed in on this device (see AuthViewModel.setAppLockPin).
    final viewModel = context.read<AuthViewModel>();
    await viewModel.setAppLockPin(newPin);

    if (!mounted) return;
    setState(() => _isSaving = false);

    SnackbarUtil.showSuccess(context, AppStrings.changePinSuccess);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: AppStrings.changePinTitle,
      showThemeToggle: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          const AuthHeader(
            icon: Icons.pin_outlined,
            title: AppStrings.changePinTitle,
            subtitle: "Update the PIN used to unlock the app on this device.",
          ),
          Text(
            AppStrings.changePinNewLabel,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryFor(context)),
          ),
          const SizedBox(height: 16),
          PinCodeInput(controller: _newPinController, autofocus: true),

          const SizedBox(height: 32),
          Text(
            AppStrings.changePinConfirmLabel,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryFor(context)),
          ),
          const SizedBox(height: 16),
          PinCodeInput(controller: _confirmPinController),

          const SizedBox(height: 40),
          AuthButton(
            text: AppStrings.changePinButton,
            isLoading: _isSaving,
            onPressed: _isSaving ? null : _submit,
          ),
        ],
      ),
    );
  }
}
