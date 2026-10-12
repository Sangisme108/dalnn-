import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';

class EmployeeOnlineOrdersScreen extends StatefulWidget {
  const EmployeeOnlineOrdersScreen({super.key});

  @override
  State<EmployeeOnlineOrdersScreen> createState() =>
      _EmployeeOnlineOrdersScreenState();
}

class _EmployeeOnlineOrdersScreenState
    extends State<EmployeeOnlineOrdersScreen> {
  bool _isLoading = true;
  String? _error;
  List<Order> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final orders = await ApiService.fetchOnlineOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String? _nextStatus(String status) {
    switch (status) {
      case 'waiting_confirm':
      case 'pending':
        return 'confirmed';
      case 'confirmed':
        return 'shipping';
      case 'shipping':
      case 'preparing':
        return 'completed';
      default:
        return null;
    }
  }

  String _nextLabel(String status) {
    switch (status) {
      case 'waiting_confirm':
      case 'pending':
        return 'Xác nhận';
      case 'confirmed':
        return 'Chuẩn bị hàng';
      case 'shipping':
      case 'preparing':
        return 'Hoàn thành';
      default:
        return 'Cập nhật';
    }
  }

  Future<void> _updateStatus(Order order, String status) async {
    try {
      final updated = await ApiService.updateOrderStatus(order.id, status);
      await DBService.orders().put(updated.id, updated);
      await _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật trạng thái đơn hàng')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không cập nhật được: $e')));
    }
  }

  String _formatCurrency(double amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} ₫';
  }

  Future<void> _openOrderDetail(Order order) async {
    try {
      final detail = await ApiService.fetchOrderDetail(order.id);
      if (!mounted) return;
      _showOrderDetail(detail);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không tải được chi tiết đơn: $e')),
      );
    }
  }

  void _showOrderDetail(Order order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (_, controller) {
            final next = _nextStatus(order.status);
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: controller,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Đơn #${order.id}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Chip(label: Text(order.status)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _info('Khách hàng', order.customerName),
                  _info('Địa chỉ', order.shippingAddress ?? 'Chưa có'),
                  _info('Thanh toán', order.paymentMethod ?? 'cash'),
                  _info('Ghi chú', order.note ?? 'Không có'),
                  const Divider(height: 28),
                  const Text(
                    'Sản phẩm',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...order.items.map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.productName),
                      subtitle: Text('Số lượng: ${item.quantity}'),
                      trailing: Text(
                        _formatCurrency(item.quantity * item.pricePerUnit),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const Divider(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tổng tiền',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _formatCurrency(order.totalAmount),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (next != null)
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _updateStatus(order, next);
                      },
                      child: Text(_nextLabel(order.status)),
                    ),
                  OutlinedButton(
                    onPressed:
                        order.status == 'cancelled' ||
                            order.status == 'completed'
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            _updateStatus(order, 'cancelled');
                          },
                    child: const Text('Huỷ đơn hàng'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xác nhận đơn hàng online'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadOrders,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadOrders,
                    child: const Text('Thử lại'),
                  ),
                ],
              )
            : _orders.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('Không có đơn online đang chờ')),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _orders.length,
                itemBuilder: (context, index) {
                  final order = _orders[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text('Đơn #${order.id}'),
                      subtitle: Text(
                        '${order.customerName}\n${_formatCurrency(order.totalAmount)}',
                      ),
                      isThreeLine: true,
                      trailing: Chip(label: Text(order.status)),
                      onTap: () => _openOrderDetail(order),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
