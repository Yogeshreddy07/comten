import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodel/auth_viewmodel.dart';
import 'welcome_screen.dart';
import 'app_lock_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkStatusAndNavigate();
  }

  Future<void> _checkStatusAndNavigate() async {
    final viewModel = context.read<AuthViewModel>();
    final activeEmployeeCode = await viewModel.getActiveEmployeeCode();
    bool completed = false;
    if (activeEmployeeCode != null) {
      completed = await viewModel.getOnboardingCompleted(activeEmployeeCode);
    }

    if (!mounted) return;

    if (activeEmployeeCode != null && completed) {
      // User is logged in and onboarding is completed. Load this device's
      // app-lock setting, and silently re-fetch the account's role/name
      // (a plain profile fetch, not a login) so the dashboard shown after
      // unlocking is correct even on a cold start, when nothing else has
      // populated them yet.
      await viewModel.loadAppLockSettings();
      await viewModel.restoreSessionIdentity(activeEmployeeCode);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AppLockScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Image.asset('assets/images/DarkThemeLogo.png', height: 180),
      ),
    );
  }
}
