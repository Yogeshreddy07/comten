import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/widgets/pin_code_input.dart';
import '../../dashboard/utils/role_dashboard_navigator.dart';
import '../viewmodel/auth_viewmodel.dart';
import '../widgets/auth_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import 'fingerprint_setup_screen.dart';

class CreatePinScreen extends StatefulWidget {
  final String employeeCode;

  const CreatePinScreen({
    super.key,
    required this.employeeCode,
  });

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isLoading = false;

  void _continue() async {
    if (_isLoading) return;

    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (pin.length != 4 || confirmPin.length != 4) {
      SnackbarUtil.showError(context, "PIN must be exactly 4 digits");
      return;
    }

    if (pin != confirmPin) {
      SnackbarUtil.showError(context, "PIN does not match");
      return;
    }

    setState(() => _isLoading = true);

    final viewModel = context.read<AuthViewModel>();
    // Device-level app lock - stored locally only, shared by every account
    // on this device (see AuthViewModel.setAppLockPin).
    await viewModel.setAppLockPin(pin);

    if (!mounted) return;

    // Left true rather than reset here (in both branches below) - this
    // screen is about to be navigated away from entirely, so re-enabling
    // the button for the moment before that happens would only reopen the
    // same race a rapid second tap exploited.
    if (viewModel.isBiometricsSupported) {
      if (!context.canPushRoute) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FingerprintSetupScreen(
            employeeCode: widget.employeeCode,
          ),
        ),
      );
    } else {
      await viewModel.saveOnboardingCompleted(widget.employeeCode, true);
      if (!mounted) return;
      await RoleDashboardNavigator.navigate(context, viewModel.role);
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mandatory onboarding step - going back would strand the user between
    // phone verification and app lock setup with no useful prior screen, so
    // back navigation is disabled entirely.
    return PopScope(
      canPop: false,
      child: AuthScaffold(
      title: "App Lock PIN",
      showBackButton: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),

          const AuthHeader(
            icon: Icons.pin_outlined,
            title: "Set an App Lock PIN",
            subtitle:
                "This PIN locks the app on this device - you'll enter it every time you open the app, no matter which account is signed in.",
          ),

          Text(
            "Enter PIN",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryFor(context)),
          ),
          const SizedBox(height: 16),
          PinCodeInput(controller: _pinController, autofocus: true),

          const SizedBox(height: 32),
          Text(
            "Confirm PIN",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryFor(context)),
          ),
          const SizedBox(height: 16),
          PinCodeInput(controller: _confirmPinController),

          const SizedBox(height: 40),
          AuthButton(
            text: "Continue",
            isLoading: _isLoading,
            onPressed: _isLoading ? null : _continue,
          ),
        ],
      ),
      ),
    );
  }
}
