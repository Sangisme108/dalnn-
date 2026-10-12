import 'package:flutter/material.dart';

import '../models/order.dart';
import '../models/order_line.dart';
import '../models/product.dart';
import '../services/db_service.dart';
import '../utils/product_asset_resolver.dart';
import '../widgets/product_image_widget.dart';

class OrderDetailScreen extends StatelessWidget {
  final Order order;

  const OrderDetailScreen({super.key, required this.order});

  String _formatCurrency(num amount) {
    final text = amount.round().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );
    return '$text₫';
  }

  String _formatDate(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  double _itemsSubtotal() {
    return order.items.fold<double>(
      0,
      (sum, item) => sum + item.quantity * item.pricePerUnit,
    );
  }

  String _statusText(String status) {
    switch (status.toLowerCase()) {
      case 'waiting_confirm':
      case 'pending':
        return 'Chờ xác nhận';
      case 'confirmed':
        return 'Đã xác nhận';
      case 'shipping':
      case 'preparing':
        return 'Đang giao';
      case 'completed':
      case 'hoàn thành':
        return 'Hoàn thành';
      case 'rejected':
        return 'Đã từ chối';
      case 'cancelled':
        return 'Đã hủy';
      default:
        return status.isEmpty ? 'Chưa có trạng thái' : status;
    }
  }

  Color _statusColor(String status) {
    final value = status.toLowerCase();
    if (value.contains('hoàn') ||
        value.contains('thành') ||
        value.contains('completed') ||
        value.contains('paid')) {
      return Colors.green;
    }
    if (value.contains('chờ') ||
        value.contains('pending') ||
        value.contains('confirm') ||
        value.contains('processing') ||
        value.contains('đang')) {
      return Colors.orange;
    }
    if (value.contains('hủy') ||
        value.contains('từ chối') ||
        value.contains('cancel') ||
        value.contains('reject') ||
        value.contains('rejected')) {
      return Colors.red;
    }
    return Colors.blueGrey;
  }

  Widget _buildLineItem(OrderLine item) {
    final product = _productForLine(item);
    final name = item.productName.isNotEmpty
        ? item.productName
        : product?.name ?? 'Sản phẩm';
    final total = item.quantity * item.pricePerUnit;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _productThumbnail(product),
          const SizedBox(width: 10),
          Text(
            'x${item.quantity}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _formatCurrency(total),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  int _totalQuantity() {
    return order.items.fold<int>(0, (sum, item) => sum + item.quantity);
  }

  Product? _productForLine(OrderLine item) {
    final products = DBService.products().values.cast<Product>();
    for (final product in products) {
      if (product.id == item.productId || product.barcode == item.productId) {
        return product;
      }
    }
    return null;
  }

  String _paymentMethodLabel(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'cash':
        return 'Tiền mặt';
      case 'card':
        return 'Thẻ';
      case 'bank_transfer':
      case 'transfer':
        return 'Chuyển khoản';
      case 'momo':
        return 'MoMo';
      case 'cod':
        return 'COD';
      case 'ewallet':
        return 'QR mô phỏng (demo)';
      case 'vnpay':
        return 'VNPay';
      default:
        return value == null || value.trim().isEmpty ? '-' : value;
    }
  }

  String _paymentStatusLabel(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'paid':
      case 'success':
        return 'Đã thanh toán';
      case 'pending':
        return 'Chờ thanh toán';
      case 'failed':
        return 'Thanh toán lỗi';
      case 'refunded':
        return 'Đã hoàn tiền';
      default:
        return value == null || value.trim().isEmpty ? '-' : value;
    }
  }

  void _showInvoiceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Center(
            child: Text(
              'HÓA ĐƠN BÁN HÀNG',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text('CỬA HÀNG ABC', style: TextStyle(fontSize: 16)),
                ),
                const Center(
                  child: Text(
                    'Địa chỉ: 123 Đường XYZ',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  'Mã đơn: ${order.id}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text('Khách hàng: ${order.customerName}'),
                Text('Ngày: ${_formatDate(order.orderDate.toLocal())}'),
                const Divider(),
                const Text(
                  'SẢN PHẨM',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                ...order.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item.productName} (x${item.quantity})',
                          ),
                        ),
                        Text(
                          _formatCurrency(item.quantity * item.pricePerUnit),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                _invoiceLine('Tạm tính', _formatCurrency(_itemsSubtotal())),
                if (order.discountAmount > 0)
                  _invoiceLine(
                    'Giảm giá',
                    '-${_formatCurrency(order.discountAmount)}',
                  ),
                _invoiceLine(
                  'Tổng thanh toán',
                  _formatCurrency(order.totalAmount),
                  isEmphasis: true,
                ),
                const SizedBox(height: 15),
                const Center(
                  child: Text(
                    'Cảm ơn quý khách!',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đang gửi lệnh in... (Mô phỏng)'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.print, size: 18),
              label: const Text('In'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(order.status);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text(
          'Chi tiết đơn hàng',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOrderHeader(statusColor),
          const SizedBox(height: 14),
          _buildOrderSummary(),
          const SizedBox(height: 14),
          _buildOrderInfoCard(),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showInvoiceDialog(context),
              icon: const Icon(Icons.print, color: Colors.white),
              label: const Text(
                'In hóa đơn',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderHeader(Color statusColor) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đơn #${order.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(order.orderDate.toLocal()),
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            _statusPill(_statusText(order.status), statusColor),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tóm tắt đơn hàng',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            if (order.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('Đơn hàng chưa có dữ liệu sản phẩm.'),
                ),
              )
            else ...[
              ...order.items.map(_buildLineItem),
              const SizedBox(height: 8),
              _summaryLine(
                'Tổng (${_totalQuantity()} món)',
                _formatCurrency(_itemsSubtotal()),
                isEmphasis: true,
              ),
              if (order.discountAmount > 0) ...[
                const SizedBox(height: 18),
                _summaryLine(
                  'Giảm giá',
                  '-${_formatCurrency(order.discountAmount)}',
                  valueColor: Colors.green.shade700,
                ),
              ],
              const SizedBox(height: 18),
              _summaryLine(
                'Tổng thanh toán',
                _formatCurrency(order.totalAmount),
                isEmphasis: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrderInfoCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thông tin đơn hàng',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _infoLine(
              'Ghi chú',
              order.note?.trim().isNotEmpty == true ? order.note! : 'Không có',
            ),
            _infoLine('Mã đơn hàng', order.id),
            _infoLine(
              'Thời gian đặt hàng',
              _formatDate(order.orderDate.toLocal()),
            ),
            _infoLine('Thanh toán', _paymentMethodLabel(order.paymentMethod)),
            _infoLine(
              'Trạng thái thanh toán',
              _paymentStatusLabel(order.paymentStatus),
            ),
            _infoLine(
              'Nhận hàng',
              order.shippingAddress?.trim().isNotEmpty == true
                  ? order.shippingAddress!
                  : 'Tại cửa hàng',
            ),
          ],
        ),
      ),
    );
  }

  Widget _productThumbnail(Product? product) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 52,
        height: 52,
        color: Colors.blue.shade50,
        child: product == null
            ? Image.asset(
                ProductAssetResolver.defaultProductAsset,
                fit: BoxFit.cover,
              )
            : ProductImageWidget(
                product: product,
                assetFallback: ProductAssetResolver.forProduct,
                height: 52,
                fit: BoxFit.cover,
              ),
      ),
    );
  }

  Widget _summaryLine(
    String label,
    String value, {
    bool isEmphasis = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isEmphasis ? Colors.black87 : Colors.black54,
                fontSize: isEmphasis ? 19 : 17,
                fontWeight: isEmphasis ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.black87,
              fontSize: isEmphasis ? 19 : 17,
              fontWeight: isEmphasis ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _invoiceLine(String label, String value, {bool isEmphasis = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isEmphasis ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isEmphasis ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
