import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onStart;
  const WelcomeScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Hero SVG image
          Container(
            color: Colors.grey.shade300,
            child: Center(
              child: SvgPicture.asset(
                'assets/images/welcome.svg',
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  Expanded(
                    child: Center(
                      child: CircleAvatar(
                        radius: 120,
                        backgroundImage: NetworkImage(
                          'https://picsum.photos/400/600',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Chào mừng\nbạn đến với cửa hàng',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Đi chợ thật là dễ dàng cho bạn',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: onStart,
                    style: ElevatedButton.styleFrom(
                      shape: StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 14,
                      ),
                    ),
                    child: const Text(
                      'Bắt đầu',
                      style: TextStyle(fontSize: 16, color: Colors.black),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
