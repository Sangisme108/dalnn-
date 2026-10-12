import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/order.dart'; // Cần import model Order
import '../services/db_service.dart'; // Cần import DBService
import '../widgets/role_bottom_navigation_bar.dart';
import '../widgets/slide_page_route.dart';
import 'checkout_screen.dart';
import 'employee.dart';
import 'employee_confirm_orders_screen.dart';
import 'order_detail_screen.dart'; // Cần import màn hình chi tiết (Giả sử bạn đã có file này)
import 'profile_route.dart';
import 'scan_product_screen.dart';

class OrderManagementScreen extends StatefulWidget {
  final String role;

  const OrderManagementScreen({super.key, required this.role});

  @override
  State<OrderManagementScreen> createState() => _OrderManagementScreenState();
}

class _OrderManagementScreenState extends State<OrderManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // String _selectedStatus = 'Tất cả'; // Có thể dùng cho lọc trạng thái

  @override
  void initState() {
    super.initState();
    _syncLatestOrders();
  }

  Future<void> _syncLatestOrders() async {
    try {
      await DBService.syncOrdersFromApi();
    } catch (_) {}
  }

  // Hàm định dạng tiền tệ
  String _formatCurrency(double amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\\d))'), (Match m) => '${m[1]},')} ₫';
  }

  bool _isCompletedOrder(Order order) {
    final status = order.status.toLowerCase();
    return status == 'completed' ||
        status == 'thành công' ||
        status == 'hoàn thành' ||
        status == 'hoÃ n thÃ nh';
  }

  bool _isOnlineOrder(Order order) {
    final orderType = order.orderType.toLowerCase();
    final deliveryMethod = (order.deliveryMethod ?? '').toLowerCase();
    return orderType == 'online' ||
        orderType == 'delivery' ||
        deliveryMethod == 'delivery';
  }

  List<Order> _filterOrdersForHistoryTab(List<Order> orders, int tabIndex) {
    final completed = orders.where(_isCompletedOrder);
    final filtered = completed.where((order) {
      final isOnline = _isOnlineOrder(order);
      return tabIndex == 0 ? !isOnline : isOnline;
    }).toList();
    filtered.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return filtered;
  }

  // Widget hiển thị một đơn hàng
  Widget _buildOrderTile(BuildContext context, Order order) {
    // Tùy biến màu sắc trạng thái (Giả định trạng thái cố định là "Hoàn thành")
    Color statusColor = Colors.green;
    String statusText = 'Hoàn thành';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        // Thông tin đơn hàng
        title: Text(
          'Mã đơn hàng: ${order.id}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Khách hàng: ${order.customerName}',
              style: const TextStyle(color: Colors.black87),
            ),
            Text(
              'Ngày: ${order.orderDate.day}/${order.orderDate.month}/${order.orderDate.year}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tổng tiền: ${_formatCurrency(order.totalAmount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        // 💡 XỬ LÝ KHI NHẤN VÀO ĐƠN HÀNG
        onTap: () {
          // Chuyển hướng sang màn hình chi tiết và truyền toàn bộ đối tượng Order
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
          );
        },
      ),
    );
  }

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
      case RoleBottomTab.employees:
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(EmployeeManagementScreen(role: widget.role)),
        );
        break;
      case RoleBottomTab.cart:
        _openCheckoutFromTab();
        break;
      case RoleBottomTab.account:
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(buildProfileScreenForRole(widget.role)),
        );
        break;
      case RoleBottomTab.invoices:
        break;
      case RoleBottomTab.confirmOrders:
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(const EmployeeConfirmOrdersScreen()),
        );
        break;
      case RoleBottomTab.scan:
        _scanAndOpenCart();
        break;
      case RoleBottomTab.offers:
      case RoleBottomTab.orders:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quản lý Đơn hàng',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
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
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      decoration: const InputDecoration(
                        hintText: 'Tìm kiếm theo mã/khách hàng',
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
          Expanded(
            child: widget.role == 'employee' || widget.role == 'admin'
                ? DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const Material(
                          color: Colors.white,
                          child: TabBar(
                            labelColor: Colors.blue,
                            unselectedLabelColor: Colors.black54,
                            indicatorColor: Colors.blue,
                            tabs: [
                              Tab(text: 'Đơn tại cửa hàng'),
                              Tab(text: 'Đơn online'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _ordersList(tabIndex: 0),
                              _ordersList(tabIndex: 1),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : _ordersList(),
          ),
        ],
      ),
      bottomNavigationBar: RoleBottomNavigationBar(
        role: widget.role,
        currentTab: RoleBottomTab.invoices,
        onTabSelected: _handleBottomTab,
      ),
    );
  }

  Widget _ordersList({int? tabIndex}) {
    return ValueListenableBuilder<Box<Order>>(
      valueListenable: DBService.orders().listenable(),
      builder: (context, box, _) {
        final allOrders = DBService.getAllOrders();
        final sourceOrders = tabIndex == null
            ? allOrders
            : _filterOrdersForHistoryTab(allOrders, tabIndex);
        final filteredOrders = sourceOrders.where((order) {
          final query = _searchQuery.toLowerCase();
          return order.id.toLowerCase().contains(query) ||
              order.customerName.toLowerCase().contains(query);
        }).toList();

        if (filteredOrders.isEmpty) {
          return const Center(child: Text('Không tìm thấy đơn hàng nào.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: filteredOrders.length,
          itemBuilder: (context, index) {
            return _buildOrderTile(context, filteredOrders[index]);
          },
        );
      },
    );
  }
}
