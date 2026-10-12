import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import 'order_detail_screen.dart';

class EmployeeConfirmOrdersScreen extends StatefulWidget {
  const EmployeeConfirmOrdersScreen({super.key});

  @override
  State<EmployeeConfirmOrdersScreen> createState() =>
      _EmployeeConfirmOrdersScreenState();
}

class _EmployeeConfirmOrdersScreenState
    extends State<EmployeeConfirmOrdersScreen> {
  static const Color _primary = Color(0xFF2563EB);
  static const Color _surface = Color(0xFFF6F7F9);
  static const Color _success = Color(0xFF16A34A);
  static const Color _danger = Color(0xFFDC2626);

  bool _isLoading = true;
  String? _error;
  String? _busyOrderId;
  String? _busyAction;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  int? _currentEmployeeId() {
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
      final employeeId = _currentEmployeeId();
      if (employeeId == null) {
        throw ApiException('Không tìm thấy nhân viên hiện tại');
      }
      final orders = await ApiService.fetchPendingOrders(employeeId);
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

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String actionLabel,
    Color actionColor = _primary,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: actionColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<String?> _rejectReasonDialog() async {
    return showDialog<String?>(
      context: context,
      builder: (_) => const _RejectReasonDialog(dangerColor: _danger),
    );
  }

  Future<void> _confirmOrder(Map<String, dynamic> order) async {
    final employeeId = _currentEmployeeId();
    final orderId = (order['order_id'] ?? order['id']).toString();
    if (employeeId == null || orderId.isEmpty) return;

    final accepted = await _confirmDialog(
      title: 'Xác nhận đơn #$orderId?',
      message: 'Đơn hàng sẽ được chuyển sang trạng thái đã xác nhận.',
      actionLabel: 'Xác nhận',
      actionColor: _success,
    );
    if (!accepted || !mounted) return;

    setState(() {
      _busyOrderId = orderId;
      _busyAction = 'confirm';
    });
    try {
      final updated = await ApiService.confirmOrder(
        employeeId: employeeId,
        orderId: orderId,
      );
      await _cacheUpdatedOrder(updated);
      await _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xác nhận đơn hàng')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyOrderId = null;
          _busyAction = null;
        });
      }
    }
  }

  Future<void> _cacheUpdatedOrder(Map<String, dynamic> order) async {
    if (order.isEmpty) return;
    final updatedOrder = Order.fromJson(order);
    await DBService.orders().put(updatedOrder.id, updatedOrder);
  }

  Future<void> _rejectOrder(Map<String, dynamic> order) async {
    final employeeId = _currentEmployeeId();
    final orderId = (order['order_id'] ?? order['id']).toString();
    if (employeeId == null || orderId.isEmpty) return;

    final reason = await _rejectReasonDialog();
    if (reason == null || !mounted) return;

    final accepted = await _confirmDialog(
      title: 'Từ chối đơn #$orderId?',
      message: 'Khách hàng sẽ thấy trạng thái bị từ chối và lý do nếu có.',
      actionLabel: 'Từ chối',
      actionColor: _danger,
    );
    if (!accepted || !mounted) return;

    setState(() {
      _busyOrderId = orderId;
      _busyAction = 'reject';
    });
    try {
      await ApiService.rejectOrder(
        employeeId: employeeId,
        orderId: orderId,
        reason: reason,
      );
      await _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã từ chối đơn hàng')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyOrderId = null;
          _busyAction = null;
        });
      }
    }
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

  String _label(dynamic value, {String fallback = 'Chưa có'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _formatDateTime(dynamic value) {
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
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute, $day/$month/${date.year}';
  }

  String _orderTypeLabel(String type) {
    switch (type) {
      case 'store_pickup':
        return 'Nhận tại cửa hàng';
      case 'delivery':
        return 'Giao hàng';
      case 'online':
        return 'Online';
      default:
        return type.isEmpty ? 'Online' : type;
    }
  }

  String _normalizedStatus(Map<String, dynamic> order) {
    final raw = (order['order_status'] ?? order['status'] ?? '').toString();
    switch (raw) {
      case 'waiting_confirm':
      case 'pending':
        return 'pending';
      case 'preparing':
        return 'shipping';
      case 'cancelled':
        return 'cancelled';
      default:
        return raw.isEmpty ? 'pending' : raw;
    }
  }

  List<Map<String, dynamic>> _ordersForTab(int tabIndex) {
    return _orders.where((order) {
      final status = _normalizedStatus(order);
      if (tabIndex == 0) return status == 'pending';
      if (tabIndex == 1) {
        return status == 'confirmed' || status == 'shipping';
      }
      if (tabIndex == 2) return status == 'rejected';
      return status == 'cancelled';
    }).toList();
  }

  dynamic _displayAmount(Map<String, dynamic> order) {
    return order['final_amount'] ??
        order['total_after_discount'] ??
        order['discounted_total'] ??
        order['totalAmount'] ??
        order['total_amount'];
  }

  String _statusText(String status) {
    switch (status) {
      case 'pending':
        return 'Chờ xác nhận';
      case 'confirmed':
        return 'Đã xác nhận';
      case 'shipping':
        return 'Đang giao';
      case 'completed':
        return 'Thành công';
      case 'rejected':
        return 'Đã từ chối';
      case 'cancelled':
        return 'Đã hủy';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
      case 'completed':
        return _success;
      case 'shipping':
        return _primary;
      case 'rejected':
      case 'cancelled':
        return _danger;
      default:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text('Xác nhận đơn online'),
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
        length: 4,
        child: Column(
          children: [
            const Material(
              color: Colors.white,
              child: TabBar(
                labelColor: _primary,
                unselectedLabelColor: Colors.black54,
                indicatorColor: _primary,
                labelPadding: EdgeInsets.zero,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: TextStyle(fontSize: 12),
                tabs: [
                  Tab(text: 'Chờ xác nhận'),
                  Tab(text: 'Đã xác nhận'),
                  Tab(text: 'Đã từ chối'),
                  Tab(text: 'Đã hủy'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ordersTab(0),
                  _ordersTab(1),
                  _ordersTab(2),
                  _ordersTab(3),
                ],
              ),
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
                SizedBox(height: 160),
                Icon(
                  Icons.assignment_turned_in_outlined,
                  size: 54,
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
    final orderId = (order['order_id'] ?? order['id']).toString();
    final items = ((order['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final orderType = _label(order['order_type'], fallback: 'online');
    final isBusy = _busyOrderId == orderId;
    final status = _normalizedStatus(order);
    final rejectionReason = (order['rejection_reason'] ?? '').toString().trim();

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
                      'Đơn #$orderId',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _statusPill(_statusText(status), _statusColor(status)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                runSpacing: 8,
                spacing: 10,
                children: [
                  _metaChip(
                    Icons.person_outline,
                    _label(order['customer_name']),
                  ),
                  _metaChip(
                    Icons.storefront_outlined,
                    _orderTypeLabel(orderType),
                  ),
                  _metaChip(
                    Icons.payments_outlined,
                    _label(order['payment_method']),
                  ),
                  _metaChip(
                    Icons.location_on_outlined,
                    _label(
                      order['shipping_address'],
                      fallback: 'Nhận tại cửa hàng',
                    ),
                  ),
                  if ((order['pickup_time'] ?? '').toString().isNotEmpty)
                    _metaChip(
                      Icons.schedule_outlined,
                      'Nhận lúc ${_formatDateTime(order['pickup_time'])}',
                    ),
                ],
              ),
              const Divider(height: 26),
              ...items.map(_itemRow),
              const Divider(height: 26),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tổng tiền',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _formatCurrency(_displayAmount(order)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1B7F4D),
                      ),
                    ),
                  ),
                ],
              ),
              if (status == 'rejected' && rejectionReason.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Lý do từ chối: $rejectionReason',
                  style: const TextStyle(
                    color: _danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (status == 'cancelled' && rejectionReason.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Lý do hủy: $rejectionReason',
                  style: const TextStyle(
                    color: _danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (status == 'pending') ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isBusy ? null : () => _rejectOrder(order),
                        icon: isBusy && _busyAction == 'reject'
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.close_rounded),
                        label: const Text('Từ chối'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _danger,
                          side: const BorderSide(color: _danger),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isBusy ? null : () => _confirmOrder(order),
                        icon: isBusy && _busyAction == 'confirm'
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: const Text('Xác nhận'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
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
    final maxWidth = MediaQuery.sizeOf(context).width - 64;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
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
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(Map<String, dynamic> item) {
    final name = _label(item['product_name'] ?? item['productName']);
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
          Flexible(
            child: Text(
              _formatCurrency(item['subtotal']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectReasonDialog extends StatefulWidget {
  final Color dangerColor;

  const _RejectReasonDialog({required this.dangerColor});

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Từ chối đơn hàng'),
      content: TextField(
        controller: _controller,
        minLines: 3,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Lý do từ chối (không bắt buộc)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.dangerColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Từ chối'),
        ),
      ],
    );
  }
}
