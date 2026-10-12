import 'package:flutter/material.dart';

import '../services/db_service.dart';
import '../services/api_service.dart';

class ProfileDetailsScreen extends StatefulWidget {
  final String email;
  final String password;
  final bool remember;

  const ProfileDetailsScreen({
    super.key,
    required this.email,
    required this.password,
    required this.remember,
  });

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _fullNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final email = widget.email.trim();

    try {
      await ApiService.register(
        fullName: _fullNameCtrl.text.trim(),
        email: email,
        password: widget.password,
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
      );
      await DBService.syncUsersFromApi();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : 'Lỗi tạo tài khoản'),
        ),
      );
      return;
    }

    if (widget.remember) {
      final settings = DBService.settings();
      settings.put('remember_email', widget.email);
      settings.delete('remember_pass');
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Tạo tài khoản thành công')));

    // pop twice: close profile details and the register screen to go back to previous flow
    Navigator.of(context).pop();
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thông tin cá nhân')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Email: ${widget.email}'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fullNameCtrl,
                  decoration: const InputDecoration(labelText: 'Họ tên'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Vui lòng nhập họ tên'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Số điện thoại'),
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Vui lòng nhập số điện thoại';
                    }
                    final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
                    if (cleaned.length < 7) return 'Số điện thoại không hợp lệ';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Địa chỉ'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Vui lòng nhập địa chỉ';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _saveProfile,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text('Hoàn tất', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
