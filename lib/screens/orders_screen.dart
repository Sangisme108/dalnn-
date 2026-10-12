import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const Color _primary = Color(0xFF1B7F4D);
  static const Color _surface = Color(0xFFF6F7F9);

  bool _isLoading = true;
  String? _error;
  String? _busyOrderId;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  int? _currentUserId() {
    final raw = DBService.settings().get('current_user_id');
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = _currentUserId();
      if (userId == null) {
        throw ApiException('Không tìm thấy người dùng hiện tại');
      }
      final orders = await ApiService.fetchMyOrders(userId);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _markReceived(Map<String, dynamic> order) async {
    final userId = _currentUserId();
    final orderId = (order['order_id'] ?? order['id']).toString();
    if (userId == null || orderId.isEmpty) return;

    setState(() => _busyOrderId = orderId);
    try {
      final updated = await ApiService.markOrderReceived(
        userId: userId,
        orderId: orderId,
      );
      await _cacheUpdatedOrder(updated);
      await _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xác nhận nhận hàng')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  Future<void> _showCancelDialog(Map<String, dynamic> order) async {
    var enteredReason = '';
    String? validationMessage;
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Hủy đơn hàng'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vui lòng nhập lý do bạn muốn hủy đơn.'),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                maxLength: 255,
                maxLines: 3,
                onChanged: (value) => enteredReason = value,
                decoration: InputDecoration(
                  labelText: 'Lý do hủy',
                  hintText: 'Ví dụ: Tôi muốn thay đổi sản phẩm',
                  errorText: validationMessage,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final value = enteredReason.trim();
                if (value.isEmpty) {
                  setDialogState(
                    () => validationMessage = 'Vui lòng nhập lý do hủy',
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Xác nhận hủy'),
            ),
          ],
        ),
      ),
    );

    if (reason == null || !mounted) return;
    await _cancelOrder(order, reason);
  }

  Future<void> _cancelOrder(Map<String, dynamic> order, String reason) async {
    final userId = _currentUserId();
    final orderId = (order['order_id'] ?? order['id']).toString();
    if (userId == null || orderId.isEmpty) return;

    setState(() => _busyOrderId = orderId);
    try {
      final updated = await ApiService.cancelMyOrder(
        userId: userId,
        orderId: orderId,
        reason: reason,
      );
      await _cacheUpdatedOrder(updated);
      await _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã hủy đơn hàng')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  Future<void> _cacheUpdatedOrder(Map<String, dynamic> order) async {
    if (order.isEmpty) return;
    final updatedOrder = Order.fromJson(order);
    await DBService.orders().put(updatedOrder.id, updatedOrder);
  }

  Future<void> _openOrderDetail(Map<String, dynamic> order) async {
    final orderId = (order['order_id'] ?? order['id']).toString();
    if (orderId.isEmpty) return;

    try {
      final detail = await ApiService.fetchOrderDetail(orderId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderDetailScreen(order: detail)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    }
  }

  String _formatCurrency(dynamic value) {
    final amount = double.tryParse(value?.toString() ?? '0') ?? 0;
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} VND';
  }

  dynamic _displayAmount(Map<String, dynamic> order) {
    return order['final_amount'] ??
        order['total_after_discount'] ??
        order['discounted_total'] ??
        order['totalAmount'] ??
        order['total_amount'];
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '';
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$d/$m/${date.year} $h:$min';
  }

  String _formatPickupTime(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '';
    final date = parsed.isUtc
        ? parsed.toLocal()
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
          ).toLocal();
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$d/$m/${date.year} $h:$min';
  }

  String _paymentLabel(String? status) {
    switch (status) {
      case 'paid':
      case 'success':
        return 'Đã thanh toán';
      case 'pending':
        return 'Chờ thanh toán';
      case 'failed':
        return 'Thanh toán thất bại';
      default:
        return status?.isNotEmpty == true ? status! : 'Chưa rõ';
    }
  }

  String _displayStatus(Map<String, dynamic> order) {
    final display = (order['display_order_status'] ?? '').toString();
    final raw = display.isNotEmpty
        ? display
        : (order['order_status'] ?? order['status'] ?? '').toString();
    switch (raw) {
      case 'waiting_confirm':
      case 'pending':
        return 'pending';
      case 'confirmed':
        return 'confirmed';
      case 'shipping':
      case 'completed':
      case 'cancelled':
        return raw;
      case 'rejected':
        return 'rejected';
      default:
        return raw.isEmpty ? 'pending' : raw;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'pending':
        return 'Chờ xác nhận';
      case 'confirmed':
        return 'Đã xác nhận';
      case 'rejected':
        return 'Đã từ chối';
      case 'cancelled':
        return 'Đã hủy';
      case 'shipping':
        return 'Đang giao';
      case 'completed':
        return 'Thành công';
      default:
        return status;
    }
  }

  bool _isHistoryOrder(Map<String, dynamic> order) {
    final status = _displayStatus(order);
    return status == 'completed' ||
        status == 'rejected' ||
        status == 'cancelled';
  }

  List<Map<String, dynamic>> _ordersForTab(int tabIndex) {
    return _orders.where((order) {
      final isHistory = _isHistoryOrder(order);
      return tabIndex == 0 ? !isHistory : isHistory;
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
      case 'completed':
        return Colors.green;
      case 'rejected':
      case 'cancelled':
        return Colors.red;
      case 'shipping':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  String _orderTypeLabel(String type) {
    switch (type) {
      case 'store_pickup':
        return 'Tại cửa hàng';
      case 'delivery':
        return 'Giao tận nhà';
      case 'online':
        return 'Online';
      default:
        return type.isEmpty ? 'Online' : type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text('Đơn hàng của tôi'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadOrders,
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const Material(
              color: Colors.white,
              child: TabBar(
                labelColor: _primary,
                unselectedLabelColor: Colors.black54,
                indicatorColor: _primary,
                tabs: [
                  Tab(text: 'Đơn hàng của tôi'),
                  Tab(text: 'Lịch sử'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(children: [_ordersTab(0), _ordersTab(1)]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ordersTab(int tabIndex) {
    final tabOrders = _ordersForTab(tabIndex);
    return RefreshIndicator(
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
          : tabOrders.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 150),
                Icon(
                  Icons.receipt_long_outlined,
                  size: 58,
                  color: Colors.black26,
                ),
                SizedBox(height: 12),
                Center(child: Text('Không có đơn hàng')),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tabOrders.length,
              itemBuilder: (context, index) => _orderCard(tabOrders[index]),
            ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final status = _displayStatus(order);
    final statusColor = _statusColor(status);
    final paymentStatus = (order['payment_status'] ?? '').toString();
    final orderType = (order['order_type'] ?? '').toString();
    final address = (order['shipping_address'] ?? '').toString().trim();
    final pickupTime = (order['pickup_time'] ?? '').toString().trim();
    final rejectionReason = (order['rejection_reason'] ?? '').toString().trim();
    final orderId = (order['order_id'] ?? order['id']).toString();
    final canMarkReceived = status == 'shipping' && orderType == 'delivery';
    final canCancel = const [
      'pending',
      'confirmed',
      'shipping',
    ].contains(status);
    final isBusy = _busyOrderId == orderId;
    final items = ((order['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openOrderDetail(order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Đơn #${order['order_id'] ?? order['id']}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _statusPill(_statusText(status), statusColor),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _metaChip(Icons.schedule, _formatDate(order['created_at'])),
                  _metaChip(
                    Icons.storefront_outlined,
                    _orderTypeLabel(orderType),
                  ),
                  _metaChip(
                    Icons.payments_outlined,
                    _paymentLabel(paymentStatus),
                  ),
                  if (address.isNotEmpty)
                    _metaChip(Icons.location_on_outlined, address),
                  if (pickupTime.isNotEmpty)
                    _metaChip(
                      Icons.schedule_outlined,
                      'Nhận lúc ${_formatPickupTime(pickupTime)}',
                    ),
                ],
              ),
              if (status == 'rejected' && rejectionReason.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    'Lý do từ chối: $rejectionReason',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (status == 'cancelled' && rejectionReason.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    'Lý do hủy: $rejectionReason',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const Divider(height: 26),
              ...items.map(_itemRow),
              const Divider(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tổng tiền',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _formatCurrency(_displayAmount(order)),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _primary,
                    ),
                  ),
                ],
              ),
              if (canCancel) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isBusy ? null : () => _showCancelDialog(order),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Hủy đơn hàng'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
              if (canMarkReceived) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isBusy ? null : () => _markReceived(order),
                    icon: isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: const Text('Đã nhận được hàng'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _itemRow(Map<String, dynamic> item) {
    final name = (item['product_name'] ?? item['productName'] ?? '').toString();
    final quantity = item['quantity'] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text('x$quantity'),
          const SizedBox(width: 12),
          Text(
            _formatCurrency(item['subtotal']),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
