import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/db_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _remember = true;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  Future<void> _submit() async {
    final fullName = _fullNameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final address = _addressCtrl.text.trim();
    final pass = _passCtrl.text;
    final confirm = _confirmPassCtrl.text;

    if (fullName.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        pass.isEmpty ||
        confirm.isEmpty) {
      _showMessage('Vui lòng điền đầy đủ thông tin bắt buộc');
      return;
    }

    if (!_validEmail(email)) {
      _showMessage('Email không đúng định dạng');
      return;
    }

    if (phone.length < 8 || phone.length > 15) {
      _showMessage('Số điện thoại không hợp lệ');
      return;
    }

    if (pass.length < 6) {
      _showMessage('Mật khẩu phải có ít nhất 6 ký tự');
      return;
    }

    if (pass != confirm) {
      _showMessage('Mật khẩu xác nhận không khớp');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ApiService.register(
        fullName: fullName,
        email: email,
        phone: phone,
        password: pass,
        address: address,
      );

      try {
        await DBService.syncUsersFromApi();
      } catch (syncError) {
        debugPrint('Đăng ký thành công nhưng đồng bộ cache lỗi: $syncError');
      }

      if (_remember) {
        await DBService.settings().put('remember_email', email);
      }
      await DBService.settings().delete('remember_pass');

      if (!mounted) return;
      _showMessage('Đăng ký khách hàng thành công. Vui lòng đăng nhập');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : ApiService.connectionErrorMessage(e);
      _showMessage(message);
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
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Đăng ký khách hàng',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              _textField(
                controller: _fullNameCtrl,
                icon: Icons.badge_outlined,
                hintText: 'Họ tên',
              ),
              const SizedBox(height: 12),
              _textField(
                controller: _emailCtrl,
                icon: Icons.email_outlined,
                hintText: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _textField(
                controller: _phoneCtrl,
                icon: Icons.phone_outlined,
                hintText: 'Số điện thoại',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              _textField(
                controller: _addressCtrl,
                icon: Icons.location_on_outlined,
                hintText: 'Địa chỉ',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                decoration: _inputDecoration(
                  icon: Icons.lock_outline,
                  hintText: 'Mật khẩu',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPassCtrl,
                obscureText: _obscureConfirm,
                decoration: _inputDecoration(
                  icon: Icons.lock_reset_outlined,
                  hintText: 'Nhập lại mật khẩu',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v ?? false),
                  ),
                  const Text('Nhớ email để đăng nhập'),
                ],
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 0, 73, 125),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(36),
                  ),
                ),
                child: Text(
                  _isSubmitting ? 'Đang tạo tài khoản...' : 'Tạo tài khoản',
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Bạn đã có tài khoản? '),
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Đăng nhập'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required IconData icon,
    required String hintText,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _inputDecoration(icon: icon, hintText: hintText),
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
