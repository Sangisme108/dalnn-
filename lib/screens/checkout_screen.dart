import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../utils/constants.dart';
import '../utils/product_asset_resolver.dart';
import '../widgets/product_image_widget.dart';
import '../widgets/role_bottom_navigation_bar.dart';
import '../widgets/slide_page_route.dart';
import 'employee.dart';
import 'employee_confirm_orders_screen.dart';
import 'order_management_screen.dart';
import 'payment_screen.dart';
import 'profile_route.dart';
import 'scan_product_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final Map<String, int> cart;
  final String role;
  final VoidCallback onCheckoutComplete;

  const CheckoutScreen({
    super.key,
    required this.cart,
    required this.role,
    required this.onCheckoutComplete,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static const Color _primary = Color(0xFF1B7F4D);
  static const Color _surface = Color(0xFFF6F7F9);
  static const Color _ink = Color(0xFF111827);

  late final Map<String, int> _editableCart;
  String? _currentUserEmail;

  String _imageFor(Product product) {
    return ProductAssetResolver.forProduct(product);
  }

  Widget _productImage(Product product) {
    return SizedBox(
      width: 58,
      height: 58,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ProductImageWidget(
          product: product,
          assetFallback: _imageFor,
          height: 58,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _editableCart = Map<String, int>.from(widget.cart);
    _currentUserEmail = DBService.currentUserEmail();
  }

  Map<String, Product> _productById(List<Product> allProducts) {
    return {for (final product in allProducts) product.id: product};
  }

  Future<void> _persistEditableCart() async {
    final email = _currentUserEmail;
    if (email != null) {
      await DBService.saveCartForUser(email, _editableCart);
    }
  }

  double _calculateTotal(Map<String, Product> productsById) {
    double total = 0;
    for (final entry in _editableCart.entries) {
      final product = productsById[entry.key];
      if (product == null) continue;
      total += product.price * entry.value;
    }
    return total;
  }

  String _formatCurrency(double amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} VND';
  }

  void _navigateToPaymentScreen() {
    if (_editableCart.isEmpty) return;

    final allProducts = DBService.getAllProducts();
    final productsById = _productById(allProducts);
    _editableCart.removeWhere((id, quantity) {
      return quantity <= 0 || !productsById.containsKey(id);
    });
    if (_editableCart.isEmpty) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy sản phẩm trong giỏ hàng')),
      );
      Future.microtask(_persistEditableCart);
      return;
    }

    final total = _calculateTotal(productsById);
    if (total > AppConstants.maxPaymentAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppConstants.maxPaymentAmountMessage),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final detailedCart = <String, int>{};
    for (final entry in _editableCart.entries) {
      final product = productsById[entry.key];
      if (product == null) continue;
      detailedCart[product.name] = entry.value;
    }

    Navigator.push(
      context,
      buildSlidePageRoute(
        PaymentScreen(
          role: widget.role,
          cartForDisplay: detailedCart,
          originalCart: Map<String, int>.from(_editableCart),
          totalAmount: total,
          onCheckoutComplete: widget.onCheckoutComplete,
        ),
      ),
    );
  }

  Future<void> _handleBottomTab(RoleBottomTab tab) async {
    if (tab == RoleBottomTab.cart) return;
    switch (tab) {
      case RoleBottomTab.home:
        Navigator.of(context).popUntil((route) => route.isFirst);
        break;
      case RoleBottomTab.scan:
        await _scanAndAppendProduct();
        break;
      case RoleBottomTab.invoices:
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(OrderManagementScreen(role: widget.role)));
        break;
      case RoleBottomTab.confirmOrders:
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(const EmployeeConfirmOrdersScreen()));
        break;
      case RoleBottomTab.account:
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(buildProfileScreenForRole(widget.role)));
        break;
      case RoleBottomTab.employees:
        Navigator.of(context).push(
          buildSlidePageRoute(EmployeeManagementScreen(role: widget.role)),
        );
        break;
      case RoleBottomTab.offers:
      case RoleBottomTab.orders:
      case RoleBottomTab.cart:
        break;
    }
  }

  Future<void> _scanAndAppendProduct() async {
    final product = await Navigator.of(
      context,
    ).push<Product?>(buildSlidePageRoute(const ScanProductScreen()));
    if (product == null || !mounted) return;
    try {
      final currentQty = _editableCart[product.id] ?? 0;
      if (currentQty + 1 > product.stockQuantity) {
        throw ApiException('Không thể thêm quá số lượng tồn kho');
      }
      setState(() {
        _editableCart[product.id] = currentQty + 1;
      });
      await _persistEditableCart();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm ${product.name} vào giỏ hàng')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _increaseQty(Product product) {
    final currentQty = _editableCart[product.id] ?? 0;
    if (currentQty >= product.stockQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} đã đạt giới hạn tồn kho')),
      );
      return;
    }
    setState(() {
      _editableCart[product.id] = currentQty + 1;
    });
    Future.microtask(_persistEditableCart);
  }

  void _decreaseQty(Product product) {
    final currentQty = _editableCart[product.id] ?? 0;
    setState(() {
      if (currentQty <= 1) {
        _editableCart.remove(product.id);
      } else {
        _editableCart[product.id] = currentQty - 1;
      }
    });
    Future.microtask(_persistEditableCart);
  }

  @override
  Widget build(BuildContext context) {
    final allProducts = DBService.getAllProducts();
    final productsById = _productById(allProducts);
    final visibleEntries = _editableCart.entries
        .where((entry) => productsById.containsKey(entry.key))
        .toList();
    final total = _calculateTotal(productsById);

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text(
          'Giỏ hàng thanh toán',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _surface,
        foregroundColor: _ink,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (visibleEntries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _checkoutHeader(visibleEntries.length),
            ),
          Expanded(
            child: visibleEntries.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: visibleEntries.length,
                    itemBuilder: (context, index) {
                      final entry = visibleEntries[index];
                      final product = productsById[entry.key]!;
                      final qty = entry.value;
                      return _lineItem(product, qty);
                    },
                  ),
          ),
          _summaryBar(total, visibleEntries.isEmpty),
        ],
      ),
      bottomNavigationBar: RoleBottomNavigationBar(
        role: widget.role,
        currentTab: RoleBottomTab.cart,
        onTabSelected: _handleBottomTab,
      ),
    );
  }

  Widget _checkoutHeader(int lineCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B7F4D), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.point_of_sale, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Đơn tại quầy',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$lineCount dòng sản phẩm trong giỏ POS',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineItem(Product product, int qty) {
    final lineTotal = product.price * qty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _productImage(product),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_formatCurrency(product.price)} / ${product.unit}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _qtyButton(Icons.remove, () => _decreaseQty(product)),
                SizedBox(
                  width: 42,
                  child: Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                _qtyButton(Icons.add, () => _increaseQty(product)),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formatCurrency(lineTotal),
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _ink,
                        ),
                      ),
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

  Widget _qtyButton(IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton.filledTonal(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFF3F4F6),
          foregroundColor: _ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _summaryBar(double total, bool empty) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tổng cộng:', style: TextStyle(fontSize: 18)),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _formatCurrency(total),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: empty ? null : _navigateToPaymentScreen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Tiếp tục thanh toán',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 54, color: Colors.black26),
          SizedBox(height: 12),
          Text(
            'Giỏ hàng trống',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
