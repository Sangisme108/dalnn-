import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/db_service.dart';
import '../services/api_service.dart';

class AddEditEmployeeScreen extends StatefulWidget {
  final User? user; // if null -> create

  const AddEditEmployeeScreen({super.key, this.user});

  @override
  State<AddEditEmployeeScreen> createState() => _AddEditEmployeeScreenState();
}

class _AddEditEmployeeScreenState extends State<AddEditEmployeeScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _email;
  late String _password;
  bool _obscurePassword = true;
  String _role = 'employee';
  String _fullName = '';
  String _phone = '';
  String _address = '';
  DateTime? _startDate;
  int _birthYear = 0;
  bool _isSaving = false;

  bool get isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final u = widget.user!;
      _email = u.email;
      _password = u.password;
      _role = u.role;
      _fullName = u.fullName;
      _phone = u.phone;
      _address = u.address;
      _birthYear = u.birthYear;
      _startDate = u.startDate;
    } else {
      _email = '';
      _password = '';
    }
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final initial = _startDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _isSaving = true);
    try {
      if (isEditing) {
        final u = widget.user!;
        u.email = _email;
        u.password = _password;
        u.role = _role;
        u.fullName = _fullName;
        u.phone = _phone;
        u.address = _address;
        if (u.userId == null) throw Exception('Thiếu user_id');
        await ApiService.updateUser(u.userId!, u);
      } else {
        final newUser = User(
          email: _email,
          password: _password,
          role: 'employee',
          fullName: _fullName,
          phone: _phone,
          address: _address,
          status: 'active',
          points: 0,
        );
        await ApiService.createUser(newUser);
      }
      await DBService.syncUsersFromApi();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing ? 'Đã cập nhật nhân viên' : 'Đã thêm nhân viên',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lỗi'),
          content: Text(e is ApiException ? e.message : e.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true); // notify caller to refresh
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Sửa nhân viên' : 'Thêm nhân viên'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                initialValue: _email,
                readOnly: isEditing,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Vui lòng nhập email';
                  }
                  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                  if (!emailRegex.hasMatch(v.trim())) {
                    return 'Email không hợp lệ';
                  }
                  return null;
                },
                onSaved: (v) => _email = v!.trim(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _password,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Vui lòng nhập mật khẩu';
                  }
                  if (v.trim().length < 6) {
                    return 'Mật khẩu tối thiểu 6 ký tự';
                  }
                  return null;
                },
                onSaved: (v) => _password = v!.trim(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: 'Nhân viên',
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Vai trò',
                  helperText: 'Tài khoản nhân viên dùng role_id = 2',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _fullName,
                decoration: const InputDecoration(labelText: 'Tên đầy đủ'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Vui lòng nhập họ tên'
                    : null,
                onSaved: (v) => _fullName = v?.trim() ?? '',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _phone,
                decoration: const InputDecoration(labelText: 'Số điện thoại'),
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Vui lòng nhập số điện thoại';
                  }
                  final phoneRegex = RegExp(r'^[0-9+\-\s]{8,15}$');
                  if (!phoneRegex.hasMatch(v.trim())) {
                    return 'Số điện thoại không hợp lệ';
                  }
                  return null;
                },
                onSaved: (v) => _phone = v?.trim() ?? '',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _address,
                decoration: const InputDecoration(labelText: 'Địa chỉ'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Vui lòng nhập địa chỉ'
                    : null,
                onSaved: (v) => _address = v?.trim() ?? '',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _birthYear == 0 ? '' : '$_birthYear',
                decoration: const InputDecoration(labelText: 'Năm sinh'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return null; // optional
                  final parsed = int.tryParse(v);
                  if (parsed == null) return 'Năm sinh không hợp lệ';
                  if (parsed < 1900 || parsed > DateTime.now().year) {
                    return 'Năm sinh không hợp lệ';
                  }
                  return null;
                },
                onSaved: (v) =>
                    _birthYear = (v == null || v.isEmpty) ? 0 : int.parse(v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _startDate == null
                          ? 'Chưa có ngày bắt đầu'
                          : 'Bắt đầu: ${_startDate!.toLocal().toIso8601String().split('T').first}',
                    ),
                  ),
                  TextButton(
                    onPressed: _pickStartDate,
                    child: const Text('Chọn ngày'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Lưu'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
