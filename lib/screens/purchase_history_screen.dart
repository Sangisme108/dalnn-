import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import 'order_detail_screen.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  bool _isLoading = true;
  String? _error;
  List<Order> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final currentUserId = DBService.settings().get('current_user_id') as int?;
      final orders = await ApiService.fetchPurchaseHistory(
        customerId: currentUserId,
      );
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

  String _formatCurrency(double amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} ₫';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử mua hàng'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadHistory,
                    child: const Text('Thử lại'),
                  ),
                ],
              )
            : _orders.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('Chưa có đơn hoàn thành')),
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
                        '${order.items.length} sản phẩm\n${order.paymentStatus ?? ''}',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        _formatCurrency(order.totalAmount),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OrderDetailScreen(order: order),
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
