import 'package:flutter/material.dart';

import '../services/api_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _identifierCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  String _method = 'EMAIL';
  String _resetToken = '';
  int _step = 0;
  bool _isSubmitting = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final identifier = _identifierCtrl.text.trim();
    if (identifier.isEmpty) {
      _showMessage(
        _method == 'EMAIL'
            ? 'Vui lòng nhập email'
            : 'Vui lòng nhập số điện thoại',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = _method == 'EMAIL'
          ? await ApiService.forgotPasswordEmail(identifier)
          : await ApiService.forgotPasswordPhone(identifier);
      if (!mounted) return;
      final demoOtp = result['demo_otp']?.toString();
      _showMessage(
        demoOtp == null || demoOtp.isEmpty
            ? (result['message'] ?? 'Đã gửi OTP').toString()
            : '${result['message']} - OTP demo: $demoOtp',
      );
      setState(() => _step = 1);
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e is ApiException ? e.message : ApiService.connectionErrorMessage(e),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _verifyOtp() async {
    final identifier = _identifierCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      _showMessage('Vui lòng nhập OTP 6 số');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final resetToken = await ApiService.verifyPasswordResetOtp(
        identifier: identifier,
        type: _method,
        otp: otp,
      );
      if (resetToken.isEmpty) {
        throw ApiException('Backend chưa trả reset_token');
      }
      if (!mounted) return;
      setState(() {
        _resetToken = resetToken;
        _step = 2;
      });
      _showMessage('OTP hợp lệ. Vui lòng đặt mật khẩu mới');
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e is ApiException ? e.message : ApiService.connectionErrorMessage(e),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resetPassword() async {
    final newPass = _newPassCtrl.text;
    final confirm = _confirmPassCtrl.text;
    if (newPass.length < 6) {
      _showMessage('Mật khẩu mới phải có ít nhất 6 ký tự');
      return;
    }
    if (newPass != confirm) {
      _showMessage('Mật khẩu xác nhận không khớp');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ApiService.resetPassword(
        resetToken: _resetToken,
        newPassword: newPass,
      );
      if (!mounted) return;
      _showMessage('Đặt lại mật khẩu thành công. Vui lòng đăng nhập');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        e is ApiException ? e.message : ApiService.connectionErrorMessage(e),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quên mật khẩu'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _methodSelector(),
              const SizedBox(height: 20),
              if (_step == 0) _requestOtpView(),
              if (_step == 1) _verifyOtpView(),
              if (_step == 2) _resetPasswordView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodSelector() {
    return Row(
      children: [
        Expanded(
          child: ChoiceChip(
            selected: _method == 'EMAIL',
            label: const Text('Gmail'),
            avatar: const Icon(Icons.email_outlined, size: 18),
            onSelected: _step == 0
                ? (_) => setState(() => _method = 'EMAIL')
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ChoiceChip(
            selected: _method == 'PHONE',
            label: const Text('Số điện thoại'),
            avatar: const Icon(Icons.phone_outlined, size: 18),
            onSelected: _step == 0
                ? (_) => setState(() => _method = 'PHONE')
                : null,
          ),
        ),
      ],
    );
  }

  Widget _requestOtpView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _identifierCtrl,
          keyboardType: _method == 'EMAIL'
              ? TextInputType.emailAddress
              : TextInputType.phone,
          decoration: _inputDecoration(
            icon: _method == 'EMAIL'
                ? Icons.email_outlined
                : Icons.phone_outlined,
            hintText: _method == 'EMAIL' ? 'Email' : 'Số điện thoại',
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton('Gửi OTP', _requestOtp),
      ],
    );
  }

  Widget _verifyOtpView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: _inputDecoration(
            icon: Icons.password_outlined,
            hintText: 'Nhập OTP 6 số',
          ),
        ),
        const SizedBox(height: 12),
        _primaryButton('Xác thực OTP', _verifyOtp),
        TextButton(
          onPressed: _isSubmitting ? null : _requestOtp,
          child: const Text('Gửi lại OTP'),
        ),
      ],
    );
  }

  Widget _resetPasswordView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _newPassCtrl,
          obscureText: _obscurePass,
          decoration: _inputDecoration(
            icon: Icons.lock_outline,
            hintText: 'Mật khẩu mới',
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePass ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPassCtrl,
          obscureText: _obscureConfirm,
          decoration: _inputDecoration(
            icon: Icons.lock_reset_outlined,
            hintText: 'Nhập lại mật khẩu mới',
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton('Đặt lại mật khẩu', _resetPassword),
      ],
    );
  }

  Widget _primaryButton(String label, Future<void> Function() onPressed) {
    return ElevatedButton(
      onPressed: _isSubmitting ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color.fromARGB(255, 0, 73, 125),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
      ),
      child: Text(_isSubmitting ? 'Đang xử lý...' : label),
    );
  }

  InputDecoration _inputDecoration({
    required IconData icon,
    required String hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      prefixIcon: Icon(icon),
      hintText: hintText,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
