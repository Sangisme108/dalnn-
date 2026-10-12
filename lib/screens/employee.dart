import 'package:flutter/material.dart';

import '../models/user.dart';
import '../models/work_shift.dart';
import '../repositories/work_shift_repository.dart';
import '../services/db_service.dart';
import '../widgets/role_bottom_navigation_bar.dart';
import '../widgets/slide_page_route.dart';
import 'employee_detail_screen.dart';
import 'employee_confirm_orders_screen.dart';
import 'add_edit_employee_screen.dart';
import 'checkout_screen.dart';
import 'order_management_screen.dart';
import 'profile_route.dart';
import 'scan_product_screen.dart';

// Employee view model used only for presentation
class Employee {
  final String name;
  final String role;
  final String email;
  final String phone;
  final String status;
  final Color statusColor;

  Employee({
    required this.name,
    required this.role,
    required this.email,
    required this.phone,
    required this.status,
    required this.statusColor,
  });
}

class EmployeeManagementScreen extends StatefulWidget {
  final String role;

  const EmployeeManagementScreen({super.key, required this.role});

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  Future<void> _openCheckoutFromTab() async {
    final email = DBService.settings().get('current_user_email') as String?;
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy người dùng hiện tại')),
      );
      return;
    }

    final cart = await DBService.loadCartForCurrentUser(email);
    if (cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Giỏ hàng đang trống')));
      return;
    }

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

  final TextEditingController _searchController = TextEditingController();
  List<User> _allUsers = [];
  List<User> _displayedUsers = [];
  List<WorkShift> _shiftBadges = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _displayedUsers = List.from(_allUsers));
      return;
    }

    setState(() {
      _displayedUsers = _allUsers.where((u) {
        final name = u.fullName.isNotEmpty ? u.fullName : u.email;
        final role = _mapRole(u.role).toLowerCase();
        return name.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            role.contains(q);
      }).toList();
    });
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await DBService.syncUsersFromApi();
      List<WorkShift> shifts = const [];
      try {
        shifts = await WorkShiftRepository.getAllShifts();
      } catch (_) {
        // Hồ sơ nhân viên vẫn phải xem được nếu API ca làm tạm lỗi.
      }
      final usersBox = DBService.users();
      final users = usersBox.values
          .cast<User>()
          .where(
            (user) =>
                user.role.toLowerCase() == 'admin' ||
                user.role.toLowerCase() == 'employee',
          )
          .toList();

      _allUsers = users;
      _displayedUsers = List.from(_allUsers);
      _shiftBadges = shifts;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Không thể tải danh sách nhân viên: $e';
      });
    }
  }

  Employee _mapUserToEmployee(User user) {
    final name = user.fullName.isNotEmpty ? user.fullName : user.email;
    final role = _mapRole(user.role);
    final phone = user.phone.isNotEmpty ? user.phone : '-';

    final isLocked = user.status.toLowerCase() == 'inactive';
    final isEmployeeRole = user.role.toLowerCase() == 'employee';
    final shift = isEmployeeRole ? _displayShiftFor(user.userId) : null;
    final workingStatus = !isEmployeeRole
        ? 'Đang hoạt động'
        : shift?.isOpen == true
        ? 'Đang làm'
        : shift != null
        ? 'Đã kết thúc'
        : 'Chưa làm';
    final status = isLocked ? 'Đã khóa' : workingStatus;
    final statusColor = isLocked
        ? Colors.red
        : (workingStatus == 'Đang làm')
        ? Colors.green
        : (workingStatus == 'Đã kết thúc')
        ? Colors.blueGrey
        : (workingStatus == 'Đang hoạt động')
        ? Colors.green
        : Colors.orange;

    return Employee(
      name: name,
      role: role,
      email: user.email,
      phone: phone,
      status: status,
      statusColor: statusColor,
    );
  }

  WorkShift? _displayShiftFor(int? employeeId) {
    if (employeeId == null) return null;
    final shifts = _shiftBadges
        .where((s) => s.employeeId == employeeId)
        .toList();
    if (shifts.isEmpty) return null;
    final open = shifts.where((s) => s.isOpen).toList()
      ..sort(_compareShiftDesc);
    if (open.isNotEmpty) return open.first;
    final sorted = List<WorkShift>.from(shifts)..sort(_compareShiftDesc);
    return sorted.first;
  }

  int _compareShiftDesc(WorkShift a, WorkShift b) {
    final aTime = a.startDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.startDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final cmp = bTime.compareTo(aTime);
    if (cmp != 0) return cmp;
    return (b.id ?? 0).compareTo(a.id ?? 0);
  }

  String _mapRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Quản lý';
      case 'employee':
        return 'Nhân viên';
      case 'customer':
        return 'Khách hàng';
      default:
        // Treat any unexpected role as regular staff
        return 'Nhân viên';
    }
  }

  Widget _buildEmployeeTileFromUser(User user) {
    final employee = _mapUserToEmployee(user);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFF4C7FFF),
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(
          employee.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              employee.role,
              style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
            ),
            Text(
              employee.phone,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            if (user.status.toLowerCase() == 'inactive')
              const Text(
                'Tài khoản inactive',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: employee.statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            employee.status,
            style: TextStyle(
              color: employee.statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        onTap: () async {
          final changed = await Navigator.of(context).push<bool?>(
            MaterialPageRoute(builder: (_) => EmployeeDetailScreen(user: user)),
          );
          if (!mounted) return;
          if (changed == true || changed == null) await _loadEmployees();
        },
      ),
    );
  }

  Future<void> _scanAndOpenCart() async {
    final product = await Navigator.of(
      context,
    ).push(buildSlidePageRoute(const ScanProductScreen()));
    if (product == null || !mounted) return;
    try {
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
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
      case RoleBottomTab.account:
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(buildProfileScreenForRole(widget.role)),
        );
        break;
      case RoleBottomTab.cart:
        _openCheckoutFromTab();
        break;
      case RoleBottomTab.scan:
        _scanAndOpenCart();
        break;
      case RoleBottomTab.employees:
      case RoleBottomTab.offers:
      case RoleBottomTab.orders:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Quản lý nhân viên',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: false,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_alt_1, size: 30),
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool?>(
                  MaterialPageRoute(
                    builder: (_) => const AddEditEmployeeScreen(),
                  ),
                );
                if (changed == true) await _loadEmployees();
              },
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF4C7FFF),
            labelColor: Colors.black87,
            tabs: [
              Tab(text: 'Quản lý'),
              Tab(text: 'Nhân viên'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Thanh tìm kiếm
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Container(
                height: 45,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.black45, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Tìm kiếm nhân viên',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Content: Tab views for owner and staff
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _loadEmployees,
                              child: const Text('Thử lại'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : TabBarView(
                      children: [
                        _buildRoleListView('admin'),
                        _buildRoleListView('employee'),
                      ],
                    ),
            ),
          ],
        ),
        bottomNavigationBar: RoleBottomNavigationBar(
          role: widget.role,
          currentTab: RoleBottomTab.employees,
          onTabSelected: _handleBottomTab,
        ),
      ),
    );
  }

  Widget _buildRoleListView(String roleKey) {
    final filtered = _displayedUsers
        .where((u) => u.role.toLowerCase() == roleKey)
        .toList();
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'Không có nhân viên phù hợp cho ${roleKey == 'admin' ? 'Quản lý' : 'Nhân viên'}',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        itemCount: filtered.length,
        itemBuilder: (context, index) =>
            _buildEmployeeTileFromUser(filtered[index]),
      ),
    );
  }
}
