import 'package:flutter/material.dart';

import '../models/order.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import 'order_detail_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  final User user;

  const CustomerDetailScreen({super.key, required this.user});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late User _user;
  bool _isLoading = true;
  String? _error;
  List<Order> _orders = [];

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await DBService.syncUsersFromApi();
      await DBService.syncOrdersFromApi();
      _refreshFromCache();
    } catch (e) {
      _refreshFromCache();
      _error = e is ApiException ? e.message : e.toString();
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  void _refreshFromCache() {
    final users = DBService.users().values.cast<User>();
    final current = users.cast<User?>().firstWhere(
      (u) => u?.userId != null && _user.userId != null
          ? u!.userId == _user.userId
          : u?.email == _user.email,
      orElse: () => null,
    );
    if (current != null) {
      _user = current;
    }

    final allOrders = DBService.orders().values.cast<Order>().toList();
    _orders = allOrders.where(_belongsToCustomer).toList()
      ..sort((a, b) => b.orderDate.compareTo(a.orderDate));
  }

  bool _belongsToCustomer(Order order) {
    if (_user.userId != null && order.customerId == _user.userId) return true;
    final orderName = order.customerName.trim().toLowerCase();
    final customerName = _displayName().trim().toLowerCase();
    return orderName.isNotEmpty && orderName == customerName;
  }

  String _displayName() =>
      _user.fullName.trim().isNotEmpty ? _user.fullName.trim() : _user.email;

  String _emptyAsDash(String value) => value.trim().isEmpty ? '-' : value;

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  String _formatDateTime(DateTime value) {
    return '${_formatDate(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  String _formatCurrency(num amount) {
    final text = amount.round().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    return '$text đ';
  }

  bool _isSuccessfulOrder(Order order) {
    final status = order.status.toLowerCase();
    return status.contains('hoàn') ||
        status.contains('completed') ||
        status.contains('success');
  }

  bool _isCanceledOrder(Order order) {
    final status = order.status.toLowerCase();
    return status.contains('hủy') ||
        status.contains('từ chối') ||
        status.contains('cancel') ||
        status.contains('reject');
  }

  int get _successfulOrders =>
      _orders.where((order) => _isSuccessfulOrder(order)).length;

  int get _canceledOrders =>
      _orders.where((order) => _isCanceledOrder(order)).length;

  double get _totalSpent =>
      _orders.fold<double>(0, (sum, order) => sum + order.totalAmount);

  double _itemsSubtotal(Order order) {
    final subtotal = order.items.fold<double>(
      0,
      (sum, item) => sum + item.quantity * item.pricePerUnit,
    );
    if (subtotal > 0) return subtotal;
    return order.totalAmount + order.discountAmount;
  }

  Color _orderStatusColor(Order order) {
    if (_isSuccessfulOrder(order)) return Colors.green;
    if (_isCanceledOrder(order)) return Colors.red;
    return Colors.orange;
  }

  String _orderStatusLabel(Order order) {
    if (_isSuccessfulOrder(order)) return 'Thành công';
    if (_isCanceledOrder(order)) return 'Đã hủy';
    if (order.status.trim().isEmpty) return 'Đang chờ';
    return 'Đang chờ';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text(
          'Chi tiết khách hàng',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        onRefresh: _loadDetail,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    _buildSyncWarning(),
                    const SizedBox(height: 12),
                  ],
                  _buildProfileCard(),
                  const SizedBox(height: 14),
                  _buildStatsGrid(),
                  const SizedBox(height: 14),
                  _buildInfoCard(),
                ],
              ),
      ),
    );
  }

  Widget _buildSyncWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Không tải được dữ liệu mới nhất. Đang hiển thị dữ liệu đã lưu.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          TextButton(onPressed: _loadDetail, child: const Text('Thử lại')),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final inactive = _user.status.toLowerCase() == 'inactive';
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
            CircleAvatar(
              radius: 32,
              backgroundColor: const Color(0xFF2563EB),
              child: Text(
                _displayName().isEmpty ? '?' : _displayName()[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  _statusPill(
                    inactive ? 'Đã khóa' : 'Đang hoạt động',
                    inactive ? Colors.red : Colors.green,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        _statCard(
          'Tổng đơn hàng',
          _orders.length.toString(),
          Icons.receipt_long_outlined,
          Colors.indigo,
          onTap: () => _openOrdersPage(title: 'Tổng đơn hàng', orders: _orders),
        ),
        _statCard(
          'Đơn thành công',
          _successfulOrders.toString(),
          Icons.check_circle_outline,
          Colors.green,
          onTap: () => _openOrdersPage(
            title: 'Đơn thành công',
            orders: _orders.where(_isSuccessfulOrder).toList(),
          ),
        ),
        _statCard(
          'Tổng chi tiêu',
          _formatCurrency(_totalSpent),
          Icons.payments_outlined,
          Colors.deepOrange,
        ),
        _statCard(
          'Đơn đã hủy',
          _canceledOrders.toString(),
          Icons.cancel_outlined,
          Colors.red,
          onTap: () => _openOrdersPage(
            title: 'Đơn đã hủy',
            orders: _orders.where(_isCanceledOrder).toList(),
          ),
        ),
      ],
    );
  }

  void _openOrdersPage({required String title, required List<Order> orders}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFFF6F7FB),
          appBar: AppBar(
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0.5,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '${orders.length} đơn',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildOrderLegend(),
                      const SizedBox(height: 12),
                      if (orders.isEmpty)
                        _emptyOrders()
                      else
                        ...orders.map(_orderTile),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
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
              'Thông tin khách hàng',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _infoRow(
              Icons.badge_outlined,
              'Mã khách hàng',
              '#${_user.userId ?? '-'}',
            ),
            _infoRow(
              Icons.card_membership_outlined,
              'Mã thành viên',
              _user.membershipCode?.isNotEmpty == true
                  ? _user.membershipCode!
                  : '-',
            ),
            _infoRow(Icons.email_outlined, 'Email', _user.email),
            _infoRow(
              Icons.phone_outlined,
              'Số điện thoại',
              _emptyAsDash(_user.phone),
            ),
            _infoRow(
              Icons.location_on_outlined,
              'Địa chỉ',
              _emptyAsDash(_user.address),
            ),
            _infoRow(
              Icons.person_outline,
              'Giới tính',
              _emptyAsDash(_user.gender),
            ),
            _infoRow(
              Icons.cake_outlined,
              'Năm sinh',
              _user.birthYear > 0 ? _user.birthYear.toString() : '-',
            ),
            _infoRow(
              Icons.stars_outlined,
              'Điểm tích lũy',
              _user.points.toString(),
            ),
            _infoRow(
              Icons.event_outlined,
              'Ngày tạo',
              _formatDate(_user.createdAt),
            ),
            _infoRow(Icons.verified_user_outlined, 'Trạng thái', _user.status),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderLegend() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _legendItem(Colors.green, 'Thành công'),
        _legendItem(Colors.red, 'Đã hủy'),
        _legendItem(Colors.orange, 'Đang chờ'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderTile(Order order) {
    final statusColor = _orderStatusColor(order);
    final subtotal = _itemsSubtotal(order);
    final hiddenItemCount = order.items.length > 4 ? order.items.length - 4 : 0;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Đơn #${order.id}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDateTime(order.orderDate),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusPill(_orderStatusLabel(order), statusColor),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _detailChip(
                  Icons.payments_outlined,
                  _paymentMethodLabel(order.paymentMethod),
                ),
                _detailChip(
                  Icons.verified_outlined,
                  _paymentStatusLabel(order.paymentStatus),
                ),
                if (order.shippingAddress?.trim().isNotEmpty == true)
                  _detailChip(Icons.local_shipping_outlined, 'Giao hàng')
                else
                  _detailChip(Icons.storefront_outlined, 'Tại cửa hàng'),
              ],
            ),
            if (order.shippingAddress?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              _compactInfoRow(
                Icons.location_on_outlined,
                'Địa chỉ giao',
                order.shippingAddress!,
              ),
            ],
            if (order.note?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _compactInfoRow(Icons.notes_outlined, 'Ghi chú', order.note!),
            ],
            const SizedBox(height: 12),
            const Text(
              'Sản phẩm',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (order.items.isEmpty)
              const Text(
                'Chưa có dữ liệu sản phẩm trong đơn này.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              )
            else
              ...order.items.take(4).map(_orderLineRow),
            if (hiddenItemCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+$hiddenItemCount sản phẩm khác',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const Divider(height: 20),
            _amountRow('Tạm tính', _formatCurrency(subtotal)),
            if (order.discountAmount > 0)
              _amountRow(
                'Giảm giá',
                '-${_formatCurrency(order.discountAmount)}',
                valueColor: Colors.green.shade700,
              ),
            _amountRow(
              'Tổng thanh toán',
              _formatCurrency(order.totalAmount),
              isEmphasis: true,
              valueColor: Colors.deepOrange.shade700,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(order: order),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Xem chi tiết đơn hàng'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.black54),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _compactInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: Colors.black54),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(color: Colors.black54)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _orderLineRow(dynamic item) {
    final lineTotal = item.quantity * item.pricePerUnit;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'x${item.quantity}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName.isEmpty
                      ? 'Sản phẩm #${item.productId}'
                      : item.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatCurrency(item.pricePerUnit)} / sản phẩm',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatCurrency(lineTotal),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _amountRow(
    String label,
    String value, {
    bool isEmphasis = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isEmphasis ? Colors.black87 : Colors.black54,
                fontWeight: isEmphasis ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.black87,
              fontSize: isEmphasis ? 16 : 14,
              fontWeight: isEmphasis ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyOrders() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, color: Colors.black38),
          SizedBox(height: 8),
          Text(
            'Khách hàng chưa có đơn mua hàng.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: Colors.black54),
          const SizedBox(width: 10),
          SizedBox(
            width: 108,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
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

  Widget _statCard(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    final content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const Spacer(),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: content,
    );
  }
}
