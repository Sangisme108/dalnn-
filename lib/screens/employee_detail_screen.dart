import 'package:flutter/material.dart';

import '../models/user.dart';
import '../repositories/work_shift_repository.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../widgets/employee_shift_card.dart';
import 'add_edit_employee_screen.dart';

class EmployeeDetailScreen extends StatefulWidget {
  final User user;

  const EmployeeDetailScreen({super.key, required this.user});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  late User user;
  bool _isLoadingSummary = true;
  String? _summaryError;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    user = widget.user;
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    if (user.userId == null) {
      setState(() {
        _isLoadingSummary = false;
        _summaryError = 'Thiếu user_id';
      });
      return;
    }

    setState(() {
      _isLoadingSummary = true;
      _summaryError = null;
    });

    try {
      final data = await WorkShiftRepository.fetchEmployeeSummary(user.userId!);
      if (!mounted) return;
      final userMap = data['user'];
      setState(() {
        if (userMap is Map) {
          user = User.fromJson(Map<String, dynamic>.from(userMap));
        }
        _summary = data;
        _summaryError = null;
        _isLoadingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = e is ApiException ? e.message : e.toString();
        _summary = _emptySummary();
        _isLoadingSummary = false;
      });
    }
  }

  Map<String, dynamic> _emptySummary() {
    return {
      'current_shift': null,
      'latest_shift': null,
      'work_status': 'unknown',
      'last_work_date': null,
      'start_time': null,
      'end_time': null,
      'total_orders': 0,
      'paid_orders_count': 0,
      'total_revenue': 0,
      'average_revenue_per_order': 0,
      'total_points_added': 0,
      'payment_history': const [],
      'payments': const [],
    };
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool?>(
      MaterialPageRoute(builder: (_) => AddEditEmployeeScreen(user: user)),
    );
    if (changed == true) {
      await DBService.syncUsersFromApi();
      await _loadSummary();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Khóa tài khoản'),
        content: Text(
          'Bạn có chắc muốn khóa tài khoản ${_displayName()} không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Khóa'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (user.userId != null) {
        await ApiService.deleteUser(user.userId!);
        await DBService.syncUsersFromApi();
      } else {
        await user.delete();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã khóa tài khoản nhân viên')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    }
  }

  bool get _isViewingOwnEmployeeAccount {
    final currentUserId = DBService.currentUserId();
    return currentUserId != null && user.userId == currentUserId;
  }

  bool get _canManageShift {
    if (user.userId == null || user.status.toLowerCase() == 'inactive') {
      return false;
    }
    if (_isViewingOwnEmployeeAccount) return true;
    final role = DBService.settings().get('current_role')?.toString() ?? '';
    return role.toLowerCase() == 'admin' &&
        user.role.toLowerCase() == 'employee';
  }

  String _displayName() =>
      user.fullName.isNotEmpty ? user.fullName : user.email;

  String _formatCurrency(num amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (match) => '${match[1]},')} ₫';
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'Chưa có';
    final dt = DateTime.tryParse(value.toString());
    if (dt == null) return value.toString();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _formatDateTime(dynamic value) {
    if (value == null) return 'Chưa có';
    final dt = DateTime.tryParse(value.toString());
    if (dt == null) return value.toString();
    return '${_formatDate(dt.toIso8601String())} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  num _numValue(String key) {
    final value = _summary?[key];
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final isInactive = user.status.toLowerCase() == 'inactive';
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Chi tiết nhân viên'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Sửa',
          ),
          IconButton(
            onPressed: isInactive ? null : _delete,
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Khóa tài khoản',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSummary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildProfileCard(),
            const SizedBox(height: 14),
            _buildSummaryContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    final isInactive = user.status.toLowerCase() == 'inactive';
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
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.blue.shade600,
                  child: Text(
                    _displayName().trim().isEmpty
                        ? '?'
                        : _displayName().trim()[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
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
                      const Text(
                        'Nhân viên',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                _statusPill(
                  isInactive ? 'inactive' : 'active',
                  isInactive ? Colors.red : Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _profileLine(Icons.email_outlined, user.email),
            _profileLine(
              Icons.phone_outlined,
              user.phone.isEmpty ? '-' : user.phone,
            ),
            _profileLine(
              Icons.location_on_outlined,
              user.address.isEmpty ? '-' : user.address,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Sửa'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isInactive ? null : _delete,
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: Text(isInactive ? 'Đã khóa' : 'Khóa'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
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

  Widget _buildSummaryContent() {
    if (_isLoadingSummary) {
      return const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Column(
      children: [
        if (_summaryError != null) ...[
          _summaryNotice(),
          const SizedBox(height: 14),
        ],
        if (user.userId != null)
          EmployeeShiftCard(
            key: ValueKey('shift_${user.userId}_${_summary?.hashCode}'),
            employeeId: user.userId!,
            employeeName: _displayName(),
            canManageShift: _canManageShift,
            initialSummary: _summary,
            onShiftChanged: _loadSummary,
          ),
        const SizedBox(height: 14),
        _buildPerformanceGrid(),
        const SizedBox(height: 14),
        _buildPaymentHistory(),
      ],
    );
  }

  Widget _buildPerformanceGrid() {
    final orderCount = _numValue('total_orders') > 0
        ? _numValue('total_orders')
        : _numValue('paid_orders_count');
    final totalRevenue = _numValue('total_revenue');
    final avgRevenue = _numValue('average_revenue_per_order');
    final totalPoints = _numValue('total_points_added');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            'Hiệu suất thanh toán',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _statCard(
              'Số đơn đã thanh toán',
              orderCount.toInt().toString(),
              Icons.receipt_long_outlined,
              Colors.indigo,
            ),
            _statCard(
              'Tổng doanh thu',
              _formatCurrency(totalRevenue),
              Icons.payments_outlined,
              Colors.green,
            ),
            _statCard(
              'Trung bình / đơn',
              _formatCurrency(avgRevenue),
              Icons.trending_up_outlined,
              Colors.deepOrange,
            ),
            _statCard(
              'Điểm đã cộng',
              totalPoints.toInt().toString(),
              Icons.stars_outlined,
              Colors.purple,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentHistory() {
    final payments =
        (_summary?['payment_history'] as List?) ??
        (_summary?['payments'] as List?) ??
        const [];
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
              'Lịch sử thanh toán',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (payments.isEmpty)
              _emptyPayments()
            else
              ...payments.map((raw) {
                final payment = Map<String, dynamic>.from(raw as Map);
                return _paymentCard(payment);
              }),
          ],
        ),
      ),
    );
  }

  Widget _paymentCard(Map<String, dynamic> payment) {
    final amount = payment['final_amount'] ?? payment['total_amount'] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.payments_outlined, color: Colors.green.shade700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đơn #${payment['order_id']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${payment['method'] ?? 'cash'} • ${_formatDateTime(payment['paid_at'])}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatCurrency(
              amount is num ? amount : num.tryParse('$amount') ?? 0,
            ),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _emptyPayments() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, color: Colors.grey.shade500),
          const SizedBox(height: 8),
          const Text(
            'Chưa có giao dịch trong ca này',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _summaryNotice() {
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
              'Không tải được dữ liệu ca làm. Đang hiển thị số liệu mặc định.',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          TextButton(onPressed: _loadSummary, child: const Text('Thử lại')),
        ],
      ),
    );
  }

  Widget _profileLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
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

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
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
          Icon(icon, color: color, size: 22),
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
  }
}
