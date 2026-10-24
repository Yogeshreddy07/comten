import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  State<ActivateAccountScreen> createState() => _ActivateAccountScreenState();
}

class _ActivateAccountScreenState extends State<ActivateAccountScreen> {
  final _code = TextEditingController();
  final _otp = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sent = false;
  String _maskedEmail = 'your registered email';
  int _remaining = 0;
  Timer? _timer;

  @override
  void dispose() { _timer?.cancel(); _code.dispose(); _otp.dispose(); super.dispose(); }

  Future<void> _send() async {
    if (Validators.employeeCode(_code.text) != null) {
      _formKey.currentState?.validate(); return;
    }
    final vm = context.read<AuthViewModel>();
    if (vm.isLoading) return;
    final result = await vm.sendActivationOtp(_code.text.trim().toUpperCase());
    if (!mounted) return;
    if (!result.success) { SnackbarUtil.showError(context, result.message); return; }
    setState(() {
      _sent = true; _remaining = 60; _otp.clear();
      _maskedEmail = result.data is Map && result.data['maskedEmail'] is String
          ? result.data['maskedEmail'] as String : 'your registered email';
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _remaining--);
      if (_remaining <= 0) timer.cancel();
    });
    SnackbarUtil.showSuccess(context, result.message);
  }

  Future<void> _verify() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final vm = context.read<AuthViewModel>();
    if (vm.isLoading) return;
    final result = await vm.verifyActivationOtp(_code.text.trim().toUpperCase(), _otp.text.trim());
    if (!mounted) return;
    if (!result.success) { SnackbarUtil.showError(context, result.message); return; }
    _timer?.cancel();
    if (!context.canPushRoute) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => CreatePasswordScreen(employeeCode: _code.text.trim().toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    return AuthScaffold(title: 'Activate Account', child: Form(key: _formKey, child: Column(children: [
      const SizedBox(height: 20),
      AuthHeader(icon: Icons.mark_email_read_outlined, title: 'Activate Account', subtitle: _sent
        ? 'Enter the 6-digit OTP sent to $_maskedEmail. Then set your password and verify your phone.'
        : 'Enter your employee code to receive an OTP at your registered email address.'),
      const SizedBox(height: 24),
      AuthTextField(controller: _code, label: 'Employee Code', icon: Icons.badge_outlined,
        readOnly: _sent || vm.isLoading, validator: Validators.employeeCode),
      if (_sent) ...[
        const SizedBox(height: 20),
        AuthTextField(controller: _otp, label: 'Email OTP', icon: Icons.pin_outlined,
          keyboardType: TextInputType.number, maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) => v != null && v.length == 6 ? null : 'Enter the complete 6-digit OTP'),
        TextButton(onPressed: vm.isLoading || _remaining > 0 ? null : _send,
          child: Text(_remaining > 0 ? 'Resend OTP in $_remaining seconds' : 'Resend OTP')),
      ],
      const SizedBox(height: 24),
      AuthButton(text: _sent ? 'Verify OTP' : 'Send OTP', isLoading: vm.isLoading,
        onPressed: vm.isLoading ? null : (_sent ? _verify : _send)),
    ])));
  }
}
