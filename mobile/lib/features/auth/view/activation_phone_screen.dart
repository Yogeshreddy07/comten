import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../viewmodel/auth_viewmodel.dart';
import '../widgets/auth_button.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/auth_text_field.dart';
import 'login_screen.dart';

class ActivationPhoneScreen extends StatefulWidget {
  const ActivationPhoneScreen({super.key});
  @override
  State<ActivationPhoneScreen> createState() => _ActivationPhoneScreenState();
}

class _ActivationPhoneScreenState extends State<ActivationPhoneScreen> {
  final _otp = TextEditingController();
  bool _sent = false;
  int _remaining = 0;
  Timer? _timer;
  void _cooldown(int seconds) {
    _timer?.cancel();
    final until = DateTime.now().add(Duration(seconds: seconds));
    setState(() => _remaining = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      final milliseconds = until.difference(DateTime.now()).inMilliseconds;
      setState(() => _remaining = milliseconds > 0 ? (milliseconds / 1000).ceil() : 0);
      if (_remaining == 0) timer.cancel();
    });
  }
  @override
  void dispose() { _timer?.cancel(); _otp.dispose(); super.dispose(); }

  Future<void> _send() async {
    final vm = context.read<AuthViewModel>();
    if (vm.isLoading || _remaining > 0) return;
    final result = await vm.sendActivationPhoneOtp();
    if (!mounted) return;
    if (!result.success) {
      if (result.data is Map && result.data['retryAfterSeconds'] is int) {
        _cooldown(result.data['retryAfterSeconds'] as int);
      }
      SnackbarUtil.showError(context, result.message); return;
    }
    setState(() { _sent = true; _otp.clear(); });
    _cooldown(result.data is Map ? (result.data['resendAfterSeconds'] as int? ?? 60) : 60);
    SnackbarUtil.showSuccess(context, 'OTP sent to your enrolled phone.');
  }

  Future<void> _verify() async {
    final vm = context.read<AuthViewModel>();
    if (vm.isLoading) return;
    if (_otp.text.length != 6) { SnackbarUtil.showError(context, 'Enter the complete 6-digit OTP'); return; }
    final result = await vm.verifyActivationPhoneOtp(_otp.text);
    if (!mounted) return;
    if (!result.success) {
      if (result.message.startsWith('OTP has expired') ||
          result.message.startsWith('Too many incorrect attempts') ||
          result.message.startsWith('No attempts left')) {
        _timer?.cancel();
        setState(() => _remaining = 0);
      }
      SnackbarUtil.showError(context, result.message); return;
    }
    _timer?.cancel();
    if (!context.canPushRoute) return;
    await showDialog<void>(context: context, barrierDismissible: false, builder: (dialogContext) => AlertDialog(
      title: const Text('Account activated'),
      content: const Text('Email and phone verified successfully. You can now log in with your employee code and password.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Go to Login'))],
    ));
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    return PopScope(canPop: false, child: AuthScaffold(title: 'Verify Phone', showBackButton: false,
      child: Column(children: [
        const SizedBox(height: 20),
        AuthHeader(icon: Icons.sms_outlined, title: 'Password set successfully',
          subtitle: 'Verify your enrolled phone ${vm.activationMaskedPhone} to complete activation. Login stays locked until verification succeeds.'),
        const SizedBox(height: 24),
        if (!_sent) AuthButton(text: _remaining > 0 ? 'Send Phone OTP in $_remaining seconds' : 'Send Phone OTP', isLoading: vm.isLoading, onPressed: vm.isLoading || _remaining > 0 ? null : _send),
        if (_sent) ...[
          AuthTextField(controller: _otp, label: 'Phone OTP', icon: Icons.pin_outlined,
            keyboardType: TextInputType.number, maxLength: 6, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
          const SizedBox(height: 20),
          AuthButton(text: 'Verify Phone OTP', isLoading: vm.isLoading, onPressed: vm.isLoading ? null : _verify),
          TextButton(onPressed: vm.isLoading || _remaining > 0 ? null : _send,
            child: Text(_remaining > 0 ? 'Resend OTP in $_remaining seconds' : 'Resend Phone OTP')),
        ],
      ])));
  }
}
