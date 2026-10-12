// lib/screens/security_info_screen.dart
import 'package:flutter/material.dart';

class SecurityInfoScreen extends StatelessWidget {
  const SecurityInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Màu nền xám nhạt
      appBar: AppBar(
        title: const Text(
          'Thông tin bảo mật',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề "Đổi mật khẩu"
            const Text(
              'Đổi mật khẩu',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // Khu vực form
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildPasswordField('Mật khẩu hiện tại'),
                    const SizedBox(height: 12),
                    _buildPasswordField('Mật khẩu mới'),
                    const SizedBox(height: 12),
                    _buildPasswordField('Nhập lại mật khẩu mới'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Nút hành động
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Nút Cập nhật
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: Thêm logic kiểm tra và đổi mật khẩu ở đây
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đang cập nhật mật khẩu...')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'Cập nhật thông tin',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Nút Hủy
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Quay lại màn hình trước
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'Hủy',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Widget TextField dùng lại cho mật khẩu
  Widget _buildPasswordField(String label) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        obscureText: true,
        decoration: InputDecoration(
          hintText: label,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}