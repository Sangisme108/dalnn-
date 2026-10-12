import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'password_login_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatelessWidget {
  final void Function(String role) onLogin;
  final bool closeOnLogin;

  const LoginScreen({
    super.key,
    required this.onLogin,
    this.closeOnLogin = false,
  });

  static const Color _primaryBlue = Color(0xFF2536B8);
  static const Color _socialBackground = Colors.white;

  void _openPasswordLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PasswordLoginScreen(
          onLogin: (role) {
            onLogin(role);
            if (closeOnLogin) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
  }

  void _showDemo(BuildContext context, String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đăng nhập $provider đang để demo giao diện')),
    );
  }

  Widget _socialButton({
    required BuildContext context,
    required String provider,
    required String asset,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: _socialBackground,
        elevation: 1,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => _showDemo(context, provider),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE2E5EA)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 24, height: 24, child: SvgPicture.asset(asset)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'Đăng nhập bằng $provider',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF222831),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: canGoBack ? const BackButton(color: Colors.black87) : null,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final heroHeight = (constraints.maxHeight * 0.40)
                .clamp(230.0, 320.0)
                .toDouble();

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      SizedBox(
                        height: heroHeight,
                        width: double.infinity,
                        child: Image.asset(
                          'assets/images/anh1.png',
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade100,
                            alignment: Alignment.center,
                            child: const Text('Hình ảnh không tải được'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      _socialButton(
                        context: context,
                        provider: 'Google',
                        asset: 'assets/images/material-icon-theme_google.svg',
                      ),
                      const SizedBox(height: 12),
                      _socialButton(
                        context: context,
                        provider: 'Facebook',
                        asset: 'assets/images/Vector.svg',
                      ),
                      const SizedBox(height: 12),
                      _socialButton(
                        context: context,
                        provider: 'Apple',
                        asset: 'assets/images/ic_baseline-apple.svg',
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: const [
                          Expanded(child: Divider(color: Colors.black38)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'hoặc',
                              style: TextStyle(color: Colors.black54),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.black38)),
                        ],
                      ),
                      const SizedBox(height: 34),
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton(
                          onPressed: () => _openPasswordLogin(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'Đăng nhập bằng mật khẩu',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Bạn chưa có tài khoản ?',
                            style: TextStyle(color: Colors.black54),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RegisterScreen(),
                              ),
                            ),
                            child: const Text(
                              'Đăng kí',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
