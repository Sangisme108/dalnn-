// dart
// lib/screens/order_success_screen.dart
import 'package:flutter/material.dart';
// Note: do not recreate HomeScreen here; we'll pop back to the existing HomeScreen

class OrderSuccessScreen extends StatelessWidget {
  final String totalAmount;
  final String paymentMethod;
  final String? orderId;
  final DateTime? paidAt;
  final int? pointsAdded;
  final int? totalPoints;
  final String? loyaltyCustomerName;
  final int pointsUsed;
  final double pointsDiscount;

  const OrderSuccessScreen({
    super.key,
    required this.totalAmount,
    required this.paymentMethod,
    this.orderId,
    this.paidAt,
    this.pointsAdded,
    this.totalPoints,
    this.loyaltyCustomerName,
    this.pointsUsed = 0,
    this.pointsDiscount = 0,
  });

  String _formatPaidAt(DateTime? value) {
    final dt = value ?? DateTime.now();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Thanh toán thành công'),
        backgroundColor: const Color(0xFF5C6BC0),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    // Icon và thông báo
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 86,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Thanh toán thành công!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Cảm ơn bạn đã mua hàng',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 28),
                    const Divider(),
                    const SizedBox(height: 18),

                    // Chi tiết thanh toán
                    if (orderId != null) ...[
                      _buildInfoRow('Mã đơn:', '#$orderId'),
                      const SizedBox(height: 12),
                    ],
                    _buildInfoRow('Đã thanh toán:', totalAmount),
                    const SizedBox(height: 12),
                    _buildInfoRow('Phương thức:', paymentMethod),
                    const SizedBox(height: 12),
                    _buildInfoRow('Thời gian:', _formatPaidAt(paidAt)),
                    if (loyaltyCustomerName != null &&
                        loyaltyCustomerName!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        'Khách tích điểm:',
                        loyaltyCustomerName ?? '-',
                      ),
                      if (pointsUsed > 0) ...[
                        const SizedBox(height: 12),
                        _buildInfoRow('Điểm đã dùng:', '-$pointsUsed'),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          'Giảm bằng điểm:',
                          '${pointsDiscount.round().toString().replaceAllMapped(RegExp(r'(\\d{1,3})(?=(\\d{3})+(?!\\d))'), (m) => '${m[1]}.')}đ',
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildInfoRow('Điểm nhận:', '+${pointsAdded ?? 0}'),
                      if (totalPoints != null) ...[
                        const SizedBox(height: 12),
                        _buildInfoRow('Điểm còn lại:', '$totalPoints'),
                      ],
                    ],
                    const SizedBox(height: 28),

                    // Nút "In hóa đơn"
                    ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Chức năng in đang được phát triển!'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('In hoá đơn'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5C6BC0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Nút "Về trang chủ" - trở về HomeScreen hiện có (không đổi tài khoản)
                    OutlinedButton.icon(
                      onPressed: () {
                        // Pop mọi route tới route đầu tiên trong stack (HomeScreen gốc)
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      },
                      icon: const Icon(Icons.home),
                      label: const Text('Về trang chủ'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        side: BorderSide(color: Colors.grey.shade400),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 18, color: Colors.black54),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
