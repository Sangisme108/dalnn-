import 'dart:io';

import 'package:flutter/material.dart';
import '../widgets/role_bottom_navigation_bar.dart';
import '../widgets/slide_page_route.dart';
import '../services/db_service.dart';
import '../models/user.dart';
import 'checkout_screen.dart';
import 'employee.dart';
import 'employee_confirm_orders_screen.dart';
import 'order_management_screen.dart';
import 'profile_edit_screen.dart';
import 'scan_product_screen.dart';
import '../widgets/employee_shift_card.dart';

class ProfileViewScreen extends StatefulWidget {
  final String role;

  const ProfileViewScreen({super.key, required this.role});

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  User? _user;

  void _loadUser() {
    final settings = DBService.settings();
    final email = settings.get('current_user_email') as String?;

    if (email != null) {
      final users = DBService.users();
      _user = users.values.cast<User?>().firstWhere(
        (u) => u?.email == email,
        orElse: () => null,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _openEditor() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProfileEditScreen()));

    setState(() => _loadUser());
  }

  Future<void> _logout() async {
    await DBService.clearAuthSession();

    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _openCheckoutFromTab() async {
    final email = DBService.settings().get('current_user_email') as String?;

    if (email == null || email.isEmpty) return;

    final cart = await DBService.loadCartForCurrentUser(email);

    if (cart.isEmpty) return;

    if (!mounted) return;

    Navigator.of(context).push(
      buildSlidePageRoute(
        CheckoutScreen(
          cart: Map<String, int>.from(cart),
          role: widget.role,
          onCheckoutComplete: () async {
            await DBService.saveCartForUser(email, <String, int>{});
          },
        ),
      ),
    );
  }

  Future<void> _scanAndOpenCart() async {
    final product = await Navigator.of(
      context,
    ).push(buildSlidePageRoute(const ScanProductScreen()));

    if (product == null || !mounted) return;

    final cart = await DBService.addProductToCurrentCart(product);

    if (!mounted) return;

    Navigator.of(context).push(
      buildSlidePageRoute(
        CheckoutScreen(
          cart: cart,
          role: widget.role,
          onCheckoutComplete: () async {
            final email = DBService.currentUserEmail();

            if (email != null) {
              await DBService.saveCartForUser(email, <String, int>{});
            }
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

      case RoleBottomTab.invoices:
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(OrderManagementScreen(role: widget.role)),
        );
        break;

      case RoleBottomTab.confirmOrders:
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(const EmployeeConfirmOrdersScreen()),
        );
        break;

      case RoleBottomTab.employees:
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(EmployeeManagementScreen(role: widget.role)),
        );
        break;

      case RoleBottomTab.account:
        break;

      case RoleBottomTab.cart:
        _openCheckoutFromTab();
        break;

      case RoleBottomTab.scan:
        _scanAndOpenCart();
        break;

      case RoleBottomTab.offers:
      case RoleBottomTab.orders:
        break;
    }
  }

  String _roleText(String role) {
    if (role == 'admin') return 'Quản lý';
    if (role == 'employee') return 'Nhân viên';
    return 'Khách hàng';
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(
        body: Center(child: Text('Không tìm thấy thông tin người dùng')),
      );
    }

    final user = _user!;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF8),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(user),

              const SizedBox(height: 16),

              if (widget.role == 'employee' && user.userId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: EmployeeShiftCard(
                    employeeId: user.userId!,
                    employeeName: user.fullName.isNotEmpty
                        ? user.fullName
                        : user.email,
                    canManageShift: true,
                  ),
                ),

              const SizedBox(height: 16),

              _buildInfoCard(user),

              const SizedBox(height: 16),

              _buildSettingButton(),

              const SizedBox(height: 12),

              _buildLogoutButton(),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: RoleBottomNavigationBar(
        role: widget.role,
        currentTab: RoleBottomTab.account,
        onTabSelected: _handleBottomTab,
      ),
    );
  }

  Widget _buildHeader(User user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12, bottom: 30),
      decoration: const BoxDecoration(
        color: Color(0xFFEAF7F2),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(35),
          bottomRight: Radius.circular(35),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, size: 28),
                ),
                const Expanded(
                  child: Text(
                    'Thông tin cá nhân',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: _openEditor,
                  icon: const Icon(Icons.edit, color: Color(0xFF2F855A)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CircleAvatar(
            radius: 62,
            backgroundColor: Colors.white,
            child: CircleAvatar(
              radius: 56,
              backgroundColor: const Color(0xFFBEEAD8),
              backgroundImage: user.avatarPath != null
                  ? FileImage(File(user.avatarPath!))
                  : null,
              child: user.avatarPath == null
                  ? const Icon(Icons.person, size: 60, color: Color(0xFF2F855A))
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            user.fullName.isNotEmpty ? user.fullName : user.email,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFDDF3E9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _roleText(user.role),
              style: const TextStyle(
                color: Color(0xFF2F855A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(User user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
      child: Column(
        children: [
          _infoRow(Icons.email_outlined, 'Email', user.email),
          _infoRow(Icons.person_outline, 'Họ tên', user.fullName),
          _infoRow(
            Icons.cake_outlined,
            'Năm sinh',
            user.birthYear == 0 ? '-' : user.birthYear.toString(),
          ),
          _infoRow(Icons.phone_outlined, 'Số điện thoại', user.phone),
          _infoRow(Icons.location_on_outlined, 'Địa chỉ', user.address),
          _infoRow(Icons.wc_outlined, 'Giới tính', user.gender),
          _infoRow(
            Icons.calendar_today_outlined,
            'Ngày bắt đầu',
            user.startDate == null
                ? '-'
                : '${user.startDate!.day}/${user.startDate!.month}/${user.startDate!.year}',
          ),
        ],
      ),
    );
  }

  Widget _buildSettingButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF1FBF6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          children: [
            Icon(Icons.settings, color: Color(0xFF2F855A)),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Cài đặt tài khoản',
                style: TextStyle(
                  color: Color(0xFF2F855A),
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: _logout,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4F4),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            children: [
              Icon(Icons.logout, color: Colors.red),
              SizedBox(width: 14),
              Text(
                'Đăng xuất',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7F2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF2F855A)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
          Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(color: Colors.black54, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
