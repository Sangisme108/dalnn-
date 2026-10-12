import 'package:flutter/material.dart';
import 'register_screen.dart';
import '../services/db_service.dart';
import '../services/api_service.dart';
import 'forgot_password_screen.dart';

class PasswordLoginScreen extends StatefulWidget {
  final void Function(String role) onLogin;
  const PasswordLoginScreen({super.key, required this.onLogin});

  @override
  State<PasswordLoginScreen> createState() => _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends State<PasswordLoginScreen> {
  final _identifierCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _remember = false;
  bool _obscurePass = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final settings = DBService.settings();
    final savedIdentifier = settings.get('remember_email');
    if (savedIdentifier != null) {
      _identifierCtrl.text = savedIdentifier as String;
      _remember = true;
    }
    settings.delete('remember_pass');
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final identifier = _identifierCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (identifier.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập email/số điện thoại và mật khẩu'),
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final user = await ApiService.login(identifier, pass);
      final role = (user['role_name'] ?? user['role'] ?? 'customer').toString();
      final settings = DBService.settings();
      if (_remember) {
        await settings.put('remember_email', identifier);
      } else {
        if (settings.containsKey('remember_email')) {
          await settings.delete('remember_email');
        }
      }
      final settings2 = DBService.settings();
      await settings2.put('current_user_id', user['user_id']);
      await settings2.put('current_user_email', user['email']);
      await settings2.put(
        'current_user_name',
        (user['full_name'] ?? user['fullName'] ?? user['email'] ?? '')
            .toString(),
      );
      await settings2.put('current_role', role);
      try {
        await DBService.syncAllFromApi();
      } catch (syncError) {
        debugPrint('Đăng nhập thành công nhưng đồng bộ API lỗi: $syncError');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đăng nhập thành công, nhưng chưa đồng bộ được dữ liệu mới',
            ),
          ),
        );
      }
      if (!mounted) return;
      widget.onLogin(role);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException
          ? e.message
          : ApiService.connectionErrorMessage(e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'Đăng nhập',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _identifierCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.person_outline),
                        hintText: 'Email hoặc số điện thoại',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscurePass,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock),
                        hintText: 'Mật khẩu',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePass
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePass = !_obscurePass),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: _remember,
                          onChanged: (v) =>
                              setState(() => _remember = v ?? false),
                        ),
                        const Expanded(child: Text('Nhớ email/số điện thoại')),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(
                            255,
                            0,
                            73,
                            125,
                          ),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(36),
                          ),
                        ),
                        child: Text(
                          _isSubmitting ? 'Đang đăng nhập...' : 'Đăng nhập',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ForgotPasswordScreen(),
                        ),
                      ),
                      child: const Text('Quên mật khẩu'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Flexible(child: Text('Bạn chưa có tài khoản? ')),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          ),
                          child: const Text('Đăng kí'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
