import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/widgets/gradient_spinner.dart';
import '../../../shared/widgets/pin_dots_indicator.dart';
import '../../../shared/widgets/theme_toggle_button.dart';
import '../../dashboard/utils/role_dashboard_navigator.dart';
import '../../settings/viewmodel/settings_view_model.dart';
import '../viewmodel/auth_viewmodel.dart';
import 'login_screen.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  bool _isLoading = false;
  bool _obscurePin = true;
  late AuthViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<AuthViewModel>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoAuthenticateBiometrics();
    });
  }

  Future<void> _autoAuthenticateBiometrics() async {
    if (_viewModel.isBiometricEnabled) {
      await _authenticateWithFingerprint();
    }
  }

  Future<void> _authenticateWithFingerprint() async {
    if (_isLoading) return;

    if (!_viewModel.isBiometricEnabled) {
      SnackbarUtil.showInfo(context, "enable finger print");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Purely local: confirms the OS biometric prompt and reveals the
    // already-active session - no backend call, no new login.
    final unlocked = await _viewModel.unlockWithBiometrics();

    if (!mounted) return;

    if (unlocked) {
      // Left true rather than reset here - this screen is about to be
      // replaced entirely, so re-enabling the button for the moment before
      // that happens would only reopen the same race a rapid second tap
      // exploited.
      await RoleDashboardNavigator.navigate(
        context,
        _viewModel.role,
        isAppUnlock: true,
      );
    } else {
      setState(() {
        _isLoading = false;
      });
      SnackbarUtil.showError(
        context,
        "Biometric authentication failed or was cancelled.",
      );
    }
  }

  Future<void> _backToLogin() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    // Same session-clear as Settings' logout (unregister this device's push
    // token, invalidate the session server-side, then clear local session
    // state) - bailing out of App Lock to the login screen should leave no
    // session behind, exactly like signing out.
    final employeeCode = _viewModel.employeeCode;
    if (employeeCode.isNotEmpty) {
      await PushNotificationService.instance.unregister(employeeCode);
    }
    if (!mounted) return;
    await context.read<SettingsViewModel>().logout();
    await _viewModel.clearActiveUser();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _onKeyPress(String val) {
    if (_isLoading) return;

    if (_pin.length < 4) {
      setState(() {
        _pin += val;
      });
    }

    if (_pin.length == 4) {
      _verifyPin();
    }
  }

  void _onDelete() {
    if (_isLoading) return;

    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  void _toggleObscurePin() {
    setState(() => _obscurePin = !_obscurePin);
  }

  Future<void> _verifyPin() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    // Purely local: compares against this device's stored app-lock PIN and
    // reveals the already-active session - no backend call, no new login.
    final unlocked = await _viewModel.verifyAppLockPin(_pin);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    if (unlocked) {
      await RoleDashboardNavigator.navigate(
        context,
        _viewModel.role,
        isAppUnlock: true,
      );
    } else {
      setState(() {
        _pin = '';
      });
      SnackbarUtil.showError(context, "Incorrect PIN");
    }
  }

  Widget _buildKeypadButton(
    BuildContext context,
    String label, {
    VoidCallback? onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(12),
      width: 72,
      height: 72,
      child: OutlinedButton(
        onPressed: onPressed ?? () => _onKeyPress(label),
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1.5),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 4,
                          right: 4,
                          top: 4,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: _isLoading ? null : _backToLogin,
                              icon: const Icon(Icons.arrow_back),
                              tooltip: 'Back to login',
                            ),
                            const Spacer(),
                            const ThemeToggleButton(),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.lock_outline,
                        size: 72,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "App Locked",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // A Stack (rather than a Row splitting space between the dots
                      // and the eye icon) so the dots are centered on the *full*
                      // available width - otherwise the eye icon's width pulls the
                      // "centered" dots visibly off from the actual center.
                      SizedBox(
                        width: double.infinity,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Center(
                              child: PinDotsIndicator(
                                length: 4,
                                filledCount: _pin.length,
                                obscureText: _obscurePin,
                                pin: _pin,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: AppDimensions.pinVisibilityIconSpacing,
                                ),
                                child: IconButton(
                                  onPressed: _toggleObscurePin,
                                  icon: Icon(
                                    _obscurePin
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: colorScheme.outline,
                                  ),
                                  tooltip: _obscurePin
                                      ? 'Show PIN'
                                      : 'Hide PIN',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Fixed-height slot so the keypad never shifts when the
                      // spinner appears; it fades/scales in rather than popping.
                      SizedBox(
                        height: 56,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: animation,
                                child: child,
                              ),
                            ),
                            child: _isLoading
                                ? const GradientSpinner(
                                    key: ValueKey('spinner'),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),

                      const Spacer(),

                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildKeypadButton(context, '1'),
                              _buildKeypadButton(context, '2'),
                              _buildKeypadButton(context, '3'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildKeypadButton(context, '4'),
                              _buildKeypadButton(context, '5'),
                              _buildKeypadButton(context, '6'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildKeypadButton(context, '7'),
                              _buildKeypadButton(context, '8'),
                              _buildKeypadButton(context, '9'),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                margin: const EdgeInsets.all(12),
                                width: 72,
                                height: 72,
                                child: IconButton(
                                  icon: Icon(
                                    Icons.fingerprint,
                                    size: 38,
                                    color: _viewModel.isBiometricEnabled
                                        ? colorScheme.primary
                                        : colorScheme.outline,
                                  ),
                                  onPressed: _isLoading
                                      ? null
                                      : _authenticateWithFingerprint,
                                ),
                              ),
                              _buildKeypadButton(context, '0'),
                              Container(
                                margin: const EdgeInsets.all(12),
                                width: 72,
                                height: 72,
                                child: IconButton(
                                  icon: Icon(
                                    Icons.backspace_outlined,
                                    size: 28,
                                    color: colorScheme.onSurface,
                                  ),
                                  onPressed: _isLoading ? null : _onDelete,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
