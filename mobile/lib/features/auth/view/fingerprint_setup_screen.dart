import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../dashboard/utils/role_dashboard_navigator.dart';
import '../viewmodel/auth_viewmodel.dart';
import '../widgets/auth_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';

class FingerprintSetupScreen extends StatefulWidget {
  final String employeeCode;

  const FingerprintSetupScreen({
    super.key,
    required this.employeeCode,
  });

  @override
  State<FingerprintSetupScreen> createState() =>
      _FingerprintSetupScreenState();
}

class _FingerprintSetupScreenState
    extends State<FingerprintSetupScreen> {
  late AuthViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<AuthViewModel>();
  }
  // Shared guard - Enable Fingerprint and Skip are mutually exclusive, so
  // both actions check and set the *same* flag instead of one each. That
  // way, whichever one is tapped first locks out the other for as long as
  // it's in flight, instead of each only blocking repeat taps of itself.
  // Neither drives any UI (no spinner, no disabled look): a blocked tap is
  // silently ignored, but the button's appearance never changes.
  bool _actionInProgress = false;

  Future<void> _enableFingerprint() async {
    if (_actionInProgress) return;
    _actionInProgress = true;

    try {
      // Device-level app lock - turns on biometric unlock for this device
      // (shared by every account signed in on it), no backend involved.
      final result = await _viewModel.enableAppLockBiometric();

      if (!mounted) return;

      if (result.success) {
        SnackbarUtil.showSuccess(context, "Fingerprint Enabled Successfully");
        await _goToDashboard();
      } else {
        _actionInProgress = false;
        SnackbarUtil.showError(context, result.message);
      }
    } catch (e) {
      if (mounted) {
        _actionInProgress = false;
        SnackbarUtil.showError(context, "An error occurred: $e");
      }
    }
  }

  Future<void> _skipSetup() async {
    if (_actionInProgress) return;
    _actionInProgress = true;

    SnackbarUtil.showInfo(context, "Setup completed. Biometrics skipped.");
    await _goToDashboard();
  }

  Future<void> _goToDashboard() async {
    await _viewModel.saveOnboardingCompleted(widget.employeeCode, true);

    await _viewModel.saveActiveEmployeeCode(widget.employeeCode);

    if (!mounted) return;
    await RoleDashboardNavigator.navigate(context, _viewModel.role);
  }

  @override
  Widget build(BuildContext context) {
    // Last onboarding step - the AppBar back icon was already hidden, but
    // that alone doesn't block the hardware/gesture back action.
    return PopScope(
      canPop: false,
      child: AuthScaffold(
      title: "Fingerprint Setup",
      showBackButton: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),

          const AuthHeader(
            icon: Icons.fingerprint,
            title: "Enable Fingerprint Login",
            subtitle: "Use your fingerprint for quick and secure access.",
          ),

          AuthButton(
            text: "Enable Fingerprint",
            isLoading: false,
            onPressed: _enableFingerprint,
          ),

          const SizedBox(height: 10),

          Center(
            child: TextButton(
              onPressed: _skipSetup,
              child: const Text("Skip"),
            ),
          ),
        ],
      ),
      ),
    );
  }
}