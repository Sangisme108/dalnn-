import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/order.dart';
import '../models/user.dart';
import '../services/db_service.dart';
import '../widgets/role_bottom_navigation_bar.dart';
import '../widgets/slide_page_route.dart';
import 'customer_online_checkout_screen.dart';
import 'customer_vouchers_screen.dart';
import 'orders_screen.dart';
import 'profile_edit_screen.dart';
import 'security_info_screen.dart';

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  User? _user;

  static const Color _primary = Color(0xFF1B7F4D);
  static const Color _accent = Color(0xFF2563EB);
  static const Color _surface = Color(0xFFF6F7F9);

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() {
    final email = DBService.currentUserEmail();
    if (email == null) {
      _user = null;
      return;
    }
    _user = DBService.users().values.cast<User?>().firstWhere(
      (user) => user?.email == email,
      orElse: () => null,
    );
  }

  Future<void> _openEditor() async {
    await Navigator.of(
      context,
    ).push(buildSlidePageRoute(const ProfileEditScreen()));
    if (mounted) setState(_loadUser);
  }

  Future<void> _openCart() async {
    final email = DBService.currentUserEmail();
    if (email == null) {
      _showMessage('Không tìm thấy người dùng hiện tại');
      return;
    }

    final cart = await DBService.loadCartForCurrentUser(email);
    if (cart.isEmpty) {
      _showMessage('Giỏ hàng đang trống');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      buildSlidePageRoute(
        CustomerOnlineCheckoutScreen(
          cart: Map<String, int>.from(cart),
          onCheckoutComplete: () async {
            await DBService.saveCartForUser(email, <String, int>{});
          },
        ),
      ),
    );
  }

  void _handleBottomTab(RoleBottomTab tab) {
    switch (tab) {
      case RoleBottomTab.home:
        Navigator.of(context).popUntil((route) => route.isFirst);
        break;
      case RoleBottomTab.offers:
        Navigator.of(
          context,
        ).pushReplacement(buildSlidePageRoute(const CustomerVouchersScreen()));
        break;
      case RoleBottomTab.cart:
        _openCart();
        break;
      case RoleBottomTab.orders:
        Navigator.of(context).push(buildSlidePageRoute(const OrdersScreen()));
        break;
      case RoleBottomTab.account:
        break;
      case RoleBottomTab.employees:
      case RoleBottomTab.invoices:
      case RoleBottomTab.confirmOrders:
      case RoleBottomTab.scan:
        break;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<Order> _customerOrders() {
    final currentUserId = DBService.currentUserId();
    final orders = DBService.getAllOrders();
    if (currentUserId != null) {
      return orders
          .where((order) => order.customerId == currentUserId)
          .toList();
    }
    return const [];
  }

  double _totalSpent(List<Order> orders) {
    return orders.fold(0, (sum, order) => sum + order.totalAmount);
  }

  String _formatCurrency(double amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} VND';
  }

  String _memberLevel(User user) {
    if (user.points >= 1000) return 'VIP';
    if (user.points >= 500) return 'Thân thiết';
    return 'Thành viên mới';
  }

  String _fallback(String value) {
    return value.trim().isEmpty ? 'Chưa cập nhật' : value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text(
          'Tài khoản của tôi',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: _surface,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _openEditor,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Chỉnh sửa',
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<Order>>(
        valueListenable: DBService.orders().listenable(),
        builder: (context, _, __) {
          _loadUser();
          final user = _user;
          if (user == null) {
            return const Center(
              child: Text('Không tìm thấy thông tin khách hàng'),
            );
          }

          final orders = _customerOrders();
          final totalSpent = _totalSpent(orders);

          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _profileHeader(user),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _statTile(
                          icon: Icons.receipt_long_outlined,
                          label: 'Đơn hàng',
                          value: orders.length.toString(),
                          color: _accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statTile(
                          icon: Icons.stars_outlined,
                          label: 'Điểm',
                          value: user.points.toString(),
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _wideStatTile('Tổng chi tiêu', _formatCurrency(totalSpent)),
                  const SizedBox(height: 16),
                  _sectionPanel(
                    title: 'Thông tin liên hệ',
                    children: [
                      _infoLine(Icons.email_outlined, 'Email', user.email),
                      _infoLine(
                        Icons.phone_outlined,
                        'Số điện thoại',
                        _fallback(user.phone),
                      ),
                      _infoLine(
                        Icons.location_on_outlined,
                        'Địa chỉ giao hàng',
                        _fallback(user.address),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _actionLine(
                    icon: Icons.local_offer_outlined,
                    label: 'Voucher của tôi',
                    subtitle: 'Lấy mã ưu đãi và xem voucher đã lưu',
                    onTap: () => Navigator.of(
                      context,
                    ).push(buildSlidePageRoute(const CustomerVouchersScreen())),
                  ),
                  const SizedBox(height: 12),
                  _actionLine(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Đơn hàng của tôi',
                    subtitle: 'Theo dõi lịch sử và trạng thái đơn hàng',
                    onTap: () => Navigator.of(
                      context,
                    ).push(buildSlidePageRoute(const OrdersScreen())),
                  ),
                  const SizedBox(height: 12),
                  _actionLine(
                    icon: Icons.lock_outline,
                    label: 'Thông tin bảo mật',
                    subtitle: 'Đổi mật khẩu và kiểm tra tài khoản',
                    onTap: () => Navigator.of(
                      context,
                    ).push(buildSlidePageRoute(const SecurityInfoScreen())),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: RoleBottomNavigationBar(
        role: 'customer',
        currentTab: RoleBottomTab.account,
        onTabSelected: _handleBottomTab,
      ),
    );
  }

  Widget _profileHeader(User user) {
    final displayName = user.fullName.isNotEmpty ? user.fullName : user.email;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: const Color(0xFFE8F5EE),
            backgroundImage: user.avatarPath != null
                ? FileImage(File(user.avatarPath!))
                : null,
            child: user.avatarPath == null
                ? const Icon(Icons.person_outline, color: _primary, size: 36)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _memberLevel(user),
                    style: const TextStyle(
                      color: Color(0xFFB45309),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideStatTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, color: _accent),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.black54)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(color: _accent, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _sectionPanel({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _infoLine(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: Colors.black45),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionLine({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF2F855A), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black26, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
