import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../services/auth_state.dart';
import '../services/db_service.dart';
import '../models/product.dart';
import 'profile_route.dart';
import 'checkout_screen.dart';
import 'customer_online_checkout_screen.dart';
import 'customer_vouchers_screen.dart';
import 'RevenueOverviewScreen.dart'; // Đã thêm
import 'product_management_screen.dart';
import 'inventory_management_screen.dart';
import 'employee.dart';
import 'employee_confirm_orders_screen.dart';
import 'work_shift_management_screen.dart';
import 'customer_management_screen.dart';
import 'orders_screen.dart';
import 'order_management_screen.dart';
import 'product_performance_report_screen.dart';
import 'scan_product_screen.dart';
import 'security_info_screen.dart';
import 'admin_vouchers_screen.dart';
import 'login_screen.dart';
import '../widgets/role_bottom_navigation_bar.dart';
import '../widgets/product_list_card.dart';
import '../widgets/slide_page_route.dart';
import 'product_detail_screen.dart';
import '../utils/product_asset_resolver.dart';
import '../utils/product_stock_utils.dart';

enum HomeFilterOption { bestSeller, priceAsc, priceDesc, inStockOnly }

// --- WIDGET CHÍNH ---
class HomeScreen extends StatefulWidget {
  final String role;
  final VoidCallback onLogout;

  const HomeScreen({super.key, required this.role, required this.onLogout});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Map<String, int> _cart = {};
  String? _currentUserEmail;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = _allCategoryLabel;
  HomeFilterOption _filterOption = HomeFilterOption.bestSeller;
  RoleBottomTab _currentBottomTab = RoleBottomTab.home;
  // *** INFINITE SCROLL LOGIC ***
  final ScrollController _scrollController = ScrollController();
  final int _productsPerPage = 6;
  int _loadedProductCount = 6;
  bool _isLoadingMore = false;
  // *****************************

  static const Color _primaryGreen = Color(0xFF1B7F4D);
  static const Color _surface = Color(0xFFF6F7F9);
  static const String _allCategoryLabel = 'Tất cả';

  bool get _isGuest => DBService.currentUserId() == null;

  Future<bool> _requireLogin({
    String message = 'Vui lòng đăng nhập để tiếp tục',
  }) async {
    if (!_isGuest) return true;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    final auth = Provider.of<AuthState>(context, listen: false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          closeOnLogin: true,
          onLogin: (role) => auth.login(role),
        ),
      ),
    );
    if (!mounted) return false;
    await _loadCurrentUserCart();
    return !_isGuest;
  }

  // Mapping sản phẩm sang đường dẫn ảnh asset (fallback khi không có ảnh từ backend)
  String _imageFor(Product p) {
    final resolvedAsset = ProductAssetResolver.forProduct(p);
    if (resolvedAsset != ProductAssetResolver.defaultProductAsset) {
      return resolvedAsset;
    }

    final id = p.id.toLowerCase();
    final name = p.name.toLowerCase();
    final barcode = (p.barcode ?? '').toLowerCase();
    final sku = barcode.isNotEmpty ? barcode : id;
    const assetBySku = {
      'prod001': 'assets/images/chuoi.png',
      'prod002': 'assets/images/dautay.jpg',
      'prod003': 'assets/images/tao.png',
      'prod004': 'assets/images/dua.jpg',
      'prod005': 'assets/images/duahau.jpg',
      'prod006': 'assets/images/xotthaixatac.jpg',
      'prod007': 'assets/images/XotBBQ.png',
      'prod008': 'assets/images/muoiotchanh.png',
      'prod009': 'assets/images/xotkimquat.jpg',
      'prod010': 'assets/images/sottrungmuoi.png',
      'prod011': 'assets/images/trathtruetea.jpg',
      'prod012': 'assets/images/tradaohatchia.jpg',
      'prod013': 'assets/images/C2.jpg',
      'prod014': 'assets/images/trahoanhai.png',
      'prod015': 'assets/images/trachanhmatong.jpg',
    };
    final assetByProductCode = assetBySku[sku];
    if (assetByProductCode != null) return assetByProductCode;

    bool anyContains(List<String> needles) {
      for (final n in needles) {
        if (id.contains(n) || name.contains(n) || barcode.contains(n)) {
          return true;
        }
      }
      return false;
    }

    if (anyContains(['banana', 'chuoi', 'chuối'])) {
      return 'assets/images/chuoi.png';
    }
    if (anyContains(['apple', 'tao', 'táo'])) {
      return 'assets/images/tao.png';
    }
    if (anyContains(['coke', 'coca'])) {
      return 'assets/images/nuoccoca.png';
    }
    if (anyContains(['diet_coke', 'diet'])) {
      return 'assets/images/dietcoca.png';
    }
    if (anyContains(['tomato', 'cachua', 'càchua', 'cà chua'])) {
      return 'assets/images/cachua.png';
    }
    if (anyContains([
      'brocoli',
      'broccoli',
      'bongcai',
      'bôngcải',
      'bông cải',
    ])) {
      return 'assets/images/bongcai.png';
    }

    // Luôn có ảnh fallback để tránh hiển thị icon trống
    if (anyContains(['bia', 'saigon', 'sai gon', 'bia sai gon'])) {
      return 'assets/images/biasaigon.jpg';
    }
    if (anyContains(['c2', 'tra xanh c2', 'trÃ  xanh c2'])) {
      return 'assets/images/C2.jpg';
    }
    if (anyContains(['dau tay', 'dautay', 'dÃ¢u tÃ¢y'])) {
      return 'assets/images/dautay.jpg';
    }
    if (anyContains(['dua', 'dá»©a'])) {
      return 'assets/images/dua.jpg';
    }
    if (anyContains(['dua hau', 'duahau', 'dÆ°a háº¥u'])) {
      return 'assets/images/duahau.jpg';
    }
    if (anyContains(['muoi ot chanh', 'muoiotchanh', 'muá»‘i á»›t chanh'])) {
      return 'assets/images/muoiotchanh.png';
    }
    if (anyContains(['nuoc cam', 'nuoccam', 'nÆ°á»›c cam'])) {
      return 'assets/products/nuoc_cam.jpg';
    }
    if (anyContains(['nuoc loc', 'nuoc suoi', 'nÆ°á»›c lá»c'])) {
      return 'assets/products/lavie.jpg';
    }
    if (anyContains([
      'sot trung muoi',
      'sottrungmuoi',
      'sá»‘t trá»©ng muá»‘i',
    ])) {
      return 'assets/images/sottrungmuoi.png';
    }
    if (anyContains(['sua tuoi', 'suatuoi', 'sá»¯a tÆ°Æ¡i'])) {
      return 'assets/images/suatuoi.jpg';
    }
    if (anyContains([
      'tra chanh mat ong',
      'trachanhmatong',
      'trÃ  chanh máº­t ong',
    ])) {
      return 'assets/images/trachanhmatong.jpg';
    }
    if (anyContains([
      'tra dao hat chia',
      'tradaohatchia',
      'trÃ  Ä‘Ã o háº¡t chia',
    ])) {
      return 'assets/images/tradaohatchia.jpg';
    }
    if (anyContains(['tra hoa nhai', 'trahoanhai', 'trÃ  hoa nhÃ i'])) {
      return 'assets/images/trahoanhai.png';
    }
    if (anyContains(['true tea', 'truetea', 'trathtruetea'])) {
      return 'assets/images/trathtruetea.jpg';
    }
    if (anyContains(['xot bbq', 'xotbbq', 'bbq'])) {
      return 'assets/images/XotBBQ.png';
    }
    if (anyContains(['xot kim quat', 'xotkimquat', 'kim quat'])) {
      return 'assets/images/xotkimquat.jpg';
    }
    if (anyContains(['xot thai xa tac', 'xotthaixatac', 'thai xa tac'])) {
      return 'assets/images/xotthaixatac.jpg';
    }

    return ProductAssetResolver.defaultProductAsset;
  }

  Widget _buildProductImage(Product p) {
    // Nguồn ảnh có thể là:
    // - URL (backend trả về) -> Image.network
    // - Path local (inventory) -> Image.file
    // - Không có -> Image.asset fallback
    final stored = (DBService.productImages().get(p.id) ?? p.imageUrl ?? '')
        .toString();
    if (stored.trim().startsWith('assets/')) {
      return Image.asset(
        stored.trim(),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (c, e, s) => Image.asset(
          _imageFor(p),
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      );
    }
    if (stored.isNotEmpty && stored.startsWith('http')) {
      return Image.network(
        stored,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (c, e, s) => Image.asset(
          _imageFor(p),
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      );
    }

    if (stored.isNotEmpty) {
      try {
        final file = File(stored);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (c, e, s) => Image.asset(
              _imageFor(p),
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          );
        }
      } catch (_) {
        // fallthrough
      }
    }

    return Image.asset(
      _imageFor(p),
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (c, e, s) => Container(
        color: Colors.grey.shade100,
        child: Image.asset(
          ProductAssetResolver.defaultProductAsset,
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedCategory = _allCategoryLabel;
    _loadCurrentUserCart();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // Hàm tải giỏ hàng người dùng
  Future<void> _loadCurrentUserCart() async {
    final settings = DBService.settings();
    final email = settings.get('current_user_email') as String?;
    _currentUserEmail = email;
    if (email == null) {
      if (mounted) setState(() => _cart.clear());
      return;
    }

    final saved = await DBService.loadCartForCurrentUser(email);
    if (mounted) {
      setState(() {
        _cart
          ..clear()
          ..addAll(saved);
      });
    }
  }

  Future<void> _persistCart() async {
    if (_currentUserEmail != null) {
      await DBService.saveCartForUser(_currentUserEmail!, _cart);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      _loadMoreProducts();
    }
  }

  void _loadMoreProducts() {
    if (_isLoadingMore) {
      return;
    }

    final allItems = DBService.products().values.toList().cast<Product>();

    if (_loadedProductCount >= allItems.length) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    // Giả lập độ trễ tải
    Future.delayed(const Duration(milliseconds: 1000), () {
      setState(() {
        _loadedProductCount += _productsPerPage;
        _isLoadingMore = false;
      });
    });
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _loadedProductCount = _productsPerPage;
    });
  }

  String _categoryOf(Product product) {
    final explicitLabel = (product.categoryName ?? '').trim();
    if (explicitLabel.isNotEmpty) {
      return explicitLabel;
    }
    final explicit = explicitLabel.toLowerCase();
    if (explicit.contains('trái') || explicit.contains('hoa quả')) {
      return 'Trái cây';
    }
    if (explicit.contains('đồ uống') || explicit.contains('nuoc')) {
      return 'Đồ uống';
    }
    if (explicit.contains('gia vị') || explicit.contains('xốt')) {
      return 'Gia vị';
    }

    final name = product.name.toLowerCase();
    final barcode = (product.barcode ?? '').toLowerCase();
    final hint = '$name $barcode';
    if (hint.contains('chuối') ||
        hint.contains('chuoi') ||
        hint.contains('dâu') ||
        hint.contains('tao') ||
        hint.contains('táo') ||
        hint.contains('dứa') ||
        hint.contains('dua hau') ||
        hint.contains('dưa hấu')) {
      return 'Trái cây';
    }
    if (hint.contains('trà') ||
        hint.contains('tea') ||
        hint.contains('coca') ||
        hint.contains('pepsi') ||
        hint.contains('c2') ||
        hint.contains('lipton')) {
      return 'Đồ uống';
    }
    if (hint.contains('xốt') ||
        hint.contains('muối') ||
        hint.contains('bbq') ||
        hint.contains('kim quất')) {
      return 'Gia vị';
    }
    return 'Khác';
  }

  List<String> _categoryFilterOptions() {
    final names = <String>{};

    for (final product in DBService.products().values) {
      final name = _categoryOf(product).trim();
      if (name.isNotEmpty && name != _allCategoryLabel) {
        names.add(name);
      }
    }

    final ordered = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [_allCategoryLabel, ...ordered];
  }

  List<Product> _applyFilters(List<Product> items) {
    Iterable<Product> result = items.where((p) => p.isActive);

    if (_selectedCategory != _allCategoryLabel) {
      result = result.where((p) => _categoryOf(p) == _selectedCategory);
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery;
      result = result.where((product) {
        final name = product.name.toLowerCase();
        final barcode = (product.barcode ?? '').toLowerCase();
        return name.contains(q) || barcode.contains(q);
      });
    }

    final list = result.toList();
    switch (_filterOption) {
      case HomeFilterOption.bestSeller:
        // Không có dữ liệu bán chạy riêng, dùng tồn kho thấp hơn làm tín hiệu bán chạy.
        list.sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
        break;
      case HomeFilterOption.priceAsc:
        list.sort((a, b) => a.price.compareTo(b.price));
        break;
      case HomeFilterOption.priceDesc:
        list.sort((a, b) => b.price.compareTo(a.price));
        break;
      case HomeFilterOption.inStockOnly:
        list.removeWhere((p) => p.stockQuantity <= 0);
        break;
    }
    return list;
  }

  String _formatVnd(double amount) {
    final value = amount.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (i > 0 && (value.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(value[i]);
    }
    return '${buffer.toString()} VNĐ';
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: RadioGroup<HomeFilterOption>(
          groupValue: _filterOption,
          onChanged: (v) {
            if (v == null) {
              return;
            }
            setState(() => _filterOption = v);
            Navigator.pop(ctx);
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text('Bộ lọc sản phẩm')),
              RadioListTile<HomeFilterOption>(
                value: HomeFilterOption.bestSeller,
                title: Text('Bán chạy'),
              ),
              RadioListTile<HomeFilterOption>(
                value: HomeFilterOption.priceAsc,
                title: Text('Giá thấp đến cao'),
              ),
              RadioListTile<HomeFilterOption>(
                value: HomeFilterOption.priceDesc,
                title: Text('Giá cao đến thấp'),
              ),
              RadioListTile<HomeFilterOption>(
                value: HomeFilterOption.inStockOnly,
                title: Text('Còn hàng'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- HÀM TÁCH WIDGET ---

  // Tách Widget Drawer
  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProfileSection(), // Tách Profile Section
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: _buildDrawerMenuItems(), // Tách Menu Items
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAdminDrawerMenuItems() {
    Widget menuIcon(IconData icon) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF7F2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF2F855A), size: 22),
      );
    }

    Widget menuCard({required Widget child}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          clipBehavior: Clip.antiAlias,
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
          child: child,
        ),
      );
    }

    Widget childItem({
      required IconData icon,
      required String title,
      required VoidCallback onTap,
    }) {
      return Container(
        color: const Color(0xFFF6FBF8),
        child: ListTile(
          contentPadding: const EdgeInsets.only(left: 28, right: 18),
          leading: Icon(icon, size: 20, color: _primaryGreen),
          title: Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: Colors.black26,
            size: 19,
          ),
          onTap: onTap,
        ),
      );
    }

    return [
      menuCard(
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: menuIcon(Icons.dashboard_outlined),
          title: const Text(
            'Tổng quan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          shape: const Border(),
          collapsedShape: const Border(),
          children: [
            childItem(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Doanh thu và lợi nhuận',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RevenueOverviewScreen(),
                  ),
                );
              },
            ),
            childItem(
              icon: Icons.bar_chart_outlined,
              title: 'Hiệu suất sản phẩm',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProductPerformanceReportScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      menuCard(
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: menuIcon(Icons.admin_panel_settings_outlined),
          title: const Text(
            'Quản lý',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          shape: const Border(),
          collapsedShape: const Border(),
          children: [
            childItem(
              icon: Icons.inventory_2_outlined,
              title: 'Sản phẩm',
              onTap: () async {
                Navigator.of(context).pop();
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProductManagementScreen(),
                  ),
                );
                if (!mounted) return;
                setState(() {});
              },
            ),
            childItem(
              icon: Icons.inventory_outlined,
              title: 'Kho hàng',
              onTap: () async {
                Navigator.of(context).pop();
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const InventoryManagementScreen(),
                  ),
                );
                if (!mounted) return;
                setState(() {});
              },
            ),
            childItem(
              icon: Icons.people_alt_outlined,
              title: 'Nhân sự',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  buildSlidePageRoute(
                    EmployeeManagementScreen(role: widget.role),
                  ),
                );
              },
            ),
            childItem(
              icon: Icons.groups_outlined,
              title: 'Khách hàng',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CustomerManagementScreen(),
                  ),
                );
              },
            ),
            childItem(
              icon: Icons.card_giftcard_outlined,
              title: 'Voucher',
              onTap: () {
                Navigator.of(context).pop();
                final token = DBService.settings().get('auth_token') ?? '';
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AdminVouchersScreen(token: token.toString()),
                  ),
                );
              },
            ),
            childItem(
              icon: Icons.schedule_outlined,
              title: 'Ca làm',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        WorkShiftManagementScreen(role: widget.role),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      menuCard(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 9,
          ),
          leading: menuIcon(Icons.receipt_long_outlined),
          title: const Text(
            'Lịch sử đơn hàng',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: Colors.black26,
            size: 20,
          ),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              buildSlidePageRoute(OrderManagementScreen(role: widget.role)),
            );
          },
        ),
      ),
      menuCard(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 9,
          ),
          leading: menuIcon(Icons.lock_outline),
          title: const Text(
            'Thông tin bảo mật',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: Colors.black26,
            size: 20,
          ),
          onTap: () async {
            Navigator.of(context).pop();
            if (!await _requireLogin(
              message: 'Vui lòng đăng nhập để xem thông tin bảo mật',
            )) {
              return;
            }
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SecurityInfoScreen()),
            );
          },
        ),
      ),
    ];
  }

  // Tách Menu Items
  List<Widget> _buildDrawerMenuItems() {
    if (widget.role == 'admin') {
      return _buildAdminDrawerMenuItems();
    }

    // Hàm helper để tạo item menu đồng bộ với thiết kế của ProfileViewScreen
    Widget _buildMenuItem({
      required IconData icon,
      required String title,
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
                // Khối bọc icon màu xanh nhạt tương tự _infoRow
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFF2F855A), size: 22),
                ),
                const SizedBox(width: 14),
                // Tiêu đề của mục menu
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                // Mũi tên điều hướng nhỏ ở góc phải
                const Icon(
                  Icons.chevron_right,
                  color: Colors.black26,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Khởi tạo item mặc định dành cho tất cả mọi người
    final List<Widget> items = [
      _buildMenuItem(
        icon: Icons.lock_outline,
        title: 'Thông tin bảo mật',
        onTap: () async {
          Navigator.of(context).pop(); // Đóng Drawer
          if (!await _requireLogin(
            message: 'Vui lòng đăng nhập để xem thông tin bảo mật',
          )) {
            return;
          }
          if (!mounted) return;
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SecurityInfoScreen()));
        },
      ),
    ];

    // Nếu là EMPLOYEE
    if (widget.role == 'employee') {
      items.insertAll(0, [
        _buildMenuItem(
          icon: Icons.schedule_outlined,
          title: 'Ca làm của tôi',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WorkShiftManagementScreen(role: widget.role),
              ),
            );
          },
        ),
        _buildMenuItem(
          icon: Icons.receipt_long_outlined,
          title: 'Lịch sử',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              buildSlidePageRoute(OrderManagementScreen(role: widget.role)),
            );
          },
        ),
        _buildMenuItem(
          icon: Icons.inventory_2_outlined,
          title: 'Quản lý sản phẩm',
          onTap: () async {
            Navigator.of(context).pop();
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ProductManagementScreen(),
              ),
            );
            if (!mounted) return;
            setState(() {});
          },
        ),
        _buildMenuItem(
          icon: Icons.inventory,
          title: 'Quản lý kho hàng',
          onTap: () async {
            Navigator.of(context).pop();
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const InventoryManagementScreen(),
              ),
            );
            if (!mounted) return;
            setState(() {});
          },
        ),
      ]);
    }

    return items;
  }

  // Tách Profile Section trong Drawer
  Widget _buildProfileSection() {
    return GestureDetector(
      onTap: () async {
        Navigator.of(context).pop();
        if (!await _requireLogin(
          message: 'Vui lòng đăng nhập để vào tài khoản',
        )) {
          return;
        }
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => buildProfileScreenForRole(widget.role),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12, width: 6),
                ),
                child: const Center(
                  child: Icon(Icons.person_outline, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Thông tin cá nhân',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Divider(),
          ],
        ),
      ),
    );
  }

  // Tách App Bar Title (Search Bar)
  // Tách App Bar Title (Search Bar)
  Widget _buildSearchBar() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: TextField(
        controller: _searchController, // Gắn controller
        decoration: InputDecoration(
          hintText: 'Tìm sản phẩm',
          prefixIcon: const Icon(Icons.search, color: Colors.black45),
          // Nút xoá (chỉ hiện khi có chữ)
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.black45),
                  onPressed: () {
                    _searchController
                        .clear(); // Xoá chữ và gọi _onSearchChanged
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 8,
          ),
        ),
      ),
    );
  }

  void _openProductDetail(Product p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: p,
          assetFallback: _imageFor,
          onAddToCart: (product, quantity) async {
            await _addToCart(product, quantity: quantity, showSnack: false);
          },
          onBuyNow: (product, quantity) async {
            final added = await _addToCart(
              product,
              quantity: quantity,
              showSnack: false,
            );
            if (!added) return;
            if (!mounted) return;
            await _openCheckoutScreen();
          },
        ),
      ),
    );
  }

  Widget _buildProductCard(Product p) {
    return ProductListCard(
      product: p,
      categoryLabel: _categoryOf(p),
      priceText: _formatVnd(p.price),
      image: _buildProductImage(p),
      onOpenDetail: () => _openProductDetail(p),
      onAddToCart: () => _addToCart(p),
    );
  }

  Future<bool> _addToCart(
    Product p, {
    int quantity = 1,
    bool showSnack = true,
  }) async {
    if (quantity <= 0) return false;
    final loggedIn = await _requireLogin(
      message: 'Vui lòng đăng nhập để thêm sản phẩm vào giỏ hàng',
    );
    if (!loggedIn) return false;
    if (!mounted) return false;
    if (!ProductStockUtils.canPurchase(p)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sản phẩm "${p.name}" đã hết hàng')),
      );
      return false;
    }

    final current = _cart[p.id] ?? 0;
    if (current + quantity > p.stockQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Chỉ còn ${p.stockQuantity} ${p.unit}, không thể thêm thêm ${p.name}.',
          ),
        ),
      );
      return false;
    }

    setState(() {
      _cart.update(p.id, (v) => v + quantity, ifAbsent: () => quantity);
    });
    Future.microtask(() => _persistCart());
    if (showSnack) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm ${p.name} vào giỏ hàng'),
          duration: const Duration(milliseconds: 1500),
        ),
      );
    }
    return true;
  }

  Future<void> _scanAndAddToCart() async {
    final loggedIn = await _requireLogin(
      message: 'Vui lòng đăng nhập để quét và thêm sản phẩm',
    );
    if (!mounted) return;
    if (!loggedIn) {
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    final product = await Navigator.of(
      context,
    ).push<Product?>(buildSlidePageRoute(const ScanProductScreen()));
    if (product == null || !mounted) {
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    try {
      final updatedCart = await DBService.addProductToCurrentCart(product);
      if (!mounted) return;
      setState(() {
        _cart
          ..clear()
          ..addAll(updatedCart);
        _currentBottomTab = RoleBottomTab.cart;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm ${product.name} vào giỏ hàng')),
      );
      await _openCheckoutScreen();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      setState(() => _currentBottomTab = RoleBottomTab.home);
    }
  }

  Future<void> _openCheckoutScreen() async {
    final loggedIn = await _requireLogin(
      message: 'Vui lòng đăng nhập để xem giỏ hàng',
    );
    if (!mounted) return;
    if (!loggedIn) {
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Giỏ hàng đang trống')));
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    final allProducts = DBService.getAllProducts();
    final validIds = allProducts.map((product) => product.id).toSet();
    _cart.removeWhere((productId, quantity) {
      return quantity <= 0 || !validIds.contains(productId);
    });
    if (_cart.isEmpty) {
      await _persistCart();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy sản phẩm trong giỏ hàng')),
      );
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    await _persistCart();
    if (!mounted) return;
    if (widget.role == 'customer') {
      await Navigator.of(context).push(
        buildSlidePageRoute(
          CustomerOnlineCheckoutScreen(
            cart: Map.from(_cart),
            onCheckoutComplete: () async {
              setState(() => _cart.clear());
              await _persistCart();
            },
          ),
        ),
      );
      if (!mounted) return;
      final email = _currentUserEmail;
      if (email != null) {
        final saved = DBService.getCartForUser(email);
        setState(() {
          _cart
            ..clear()
            ..addAll(saved);
        });
      }
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    await Navigator.of(context).push(
      buildSlidePageRoute(
        CheckoutScreen(
          cart: Map.from(_cart),
          role: widget.role,
          onCheckoutComplete: () async {
            setState(() => _cart.clear());
            await _persistCart();
          },
        ),
      ),
    );
    if (!mounted) return;
    final email = _currentUserEmail;
    if (email != null) {
      final saved = DBService.getCartForUser(email);
      setState(() {
        _cart
          ..clear()
          ..addAll(saved);
      });
    }
    setState(() => _currentBottomTab = RoleBottomTab.home);
  }

  void _handleBottomTab(RoleBottomTab tab) async {
    switch (tab) {
      case RoleBottomTab.home:
        setState(() => _currentBottomTab = tab);
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
        break;
      case RoleBottomTab.employees:
        setState(() => _currentBottomTab = tab);
        Navigator.of(context).push(
          buildSlidePageRoute(EmployeeManagementScreen(role: widget.role)),
        );
        break;
      case RoleBottomTab.scan:
        setState(() => _currentBottomTab = tab);
        await _scanAndAddToCart();
        break;
      case RoleBottomTab.invoices:
        setState(() => _currentBottomTab = tab);
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(OrderManagementScreen(role: widget.role)));
        break;
      case RoleBottomTab.confirmOrders:
        setState(() => _currentBottomTab = tab);
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(const EmployeeConfirmOrdersScreen()));
        break;
      case RoleBottomTab.offers:
        if (!await _requireLogin(
          message: 'Vui lòng đăng nhập để xem ưu đãi của bạn',
        )) {
          if (!mounted) return;
          setState(() => _currentBottomTab = RoleBottomTab.home);
          return;
        }
        if (!mounted) return;
        setState(() => _currentBottomTab = tab);
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(const CustomerVouchersScreen()));
        break;
      case RoleBottomTab.cart:
        if (_currentBottomTab != RoleBottomTab.cart) {
          setState(() => _currentBottomTab = RoleBottomTab.cart);
        }
        await _openCheckoutScreen();
        break;
      case RoleBottomTab.orders:
        if (!await _requireLogin(
          message: 'Vui lòng đăng nhập để xem đơn hàng',
        )) {
          if (!mounted) return;
          setState(() => _currentBottomTab = RoleBottomTab.home);
          return;
        }
        if (!mounted) return;
        setState(() => _currentBottomTab = tab);
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OrdersScreen()));
        break;
      case RoleBottomTab.account:
        if (!await _requireLogin(
          message: 'Vui lòng đăng nhập để vào tài khoản',
        )) {
          if (!mounted) return;
          setState(() => _currentBottomTab = RoleBottomTab.home);
          return;
        }
        if (!mounted) return;
        setState(() => _currentBottomTab = tab);
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(buildProfileScreenForRole(widget.role)));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _surface,
      drawer: _buildDrawer(), // Sử dụng Widget đã tách
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.black87),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: _buildSearchBar(), // Sử dụng Widget đã tách
        actions: [
          if (_isGuest)
            IconButton(
              onPressed: () =>
                  _requireLogin(message: 'Vui lòng đăng nhập để vào tài khoản'),
              icon: const Icon(Icons.login, color: Colors.black87),
              tooltip: 'Đăng nhập',
            )
          else
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout, color: Colors.black87),
              tooltip: 'Đăng xuất',
            ),
        ],
      ),

      // LOẠI BỎ SingleChildScrollView
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Promo banner (Image)
            const _PromoBanner(), // Tách thành Widget riêng
            const SizedBox(height: 18),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sản phẩm',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: DBService.products().listenable(),
                  builder: (context, Box<Product> box, _) {
                    final total = _applyFilters(
                      box.values.toList().cast<Product>(),
                    ).length;
                    return Text(
                      '$total mặt hàng',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _categoryFilterOptions()
                          .map(
                            (category) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(category),
                                selected: _selectedCategory == category,
                                selectedColor: _primaryGreen.withValues(
                                  alpha: 0.14,
                                ),
                                labelStyle: TextStyle(
                                  color: _selectedCategory == category
                                      ? _primaryGreen
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                                side: BorderSide(
                                  color: _selectedCategory == category
                                      ? _primaryGreen.withValues(alpha: 0.35)
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    _selectedCategory = category;
                                    _loadedProductCount = _productsPerPage;
                                  });
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _openFilterSheet,
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'Bộ lọc',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Danh sách sản phẩm (Đã thêm Expanded cho Infinite Scrolling)
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: DBService.products().listenable(),
                builder: (context, Box<Product> box, _) {
                  final allItems = box.values.toList().cast<Product>();
                  final filteredItems = _applyFilters(allItems);

                  // 2. ✅ SỬA LỖI Ở ĐÂY: Gán kết quả cho biến
                  final itemsToShow = filteredItems
                      .take(_loadedProductCount)
                      .toList();
                  final hasMore = filteredItems.length > itemsToShow.length;

                  // 3. Kiểm tra danh sách rỗng
                  if (itemsToShow.isEmpty) {
                    if (_searchQuery.isNotEmpty ||
                        _selectedCategory != 'Tất cả') {
                      return const Center(
                        child: Text('Không tìm thấy sản phẩm nào.'),
                      );
                    }
                    return const _NoProductsFound();
                  }

                  // 4. Trả về GridView
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width >= 1000
                          ? 5
                          : width >= 760
                          ? 4
                          : width >= 520
                          ? 3
                          : 2;
                      return GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.70,
                        ),
                        itemCount: itemsToShow.length + (hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == itemsToShow.length && hasMore) {
                            return const _LoadingFooter();
                          }

                          final Product p = itemsToShow[index];
                          return _buildProductCard(p);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),

      floatingActionButton: null,
      bottomNavigationBar: RoleBottomNavigationBar(
        role: widget.role,
        currentTab: _currentBottomTab,
        onTabSelected: _handleBottomTab,
      ),
    );
  }

  // Tách Cart Sheet
  // ignore: unused_element
  void _openCartSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, modalSetState) {
            final productsBox = DBService.products();
            final items = productsBox.values
                .where((p) => _cart.containsKey(p.id))
                .toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.5,
              minChildSize: 0.25,
              maxChildSize: 0.9,
              builder: (_, controller) => Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const _ModalDragHandle(), // Tách Widget
                    const SizedBox(height: 12),
                    const Text(
                      'Giỏ hàng',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: items.isEmpty
                          ? const Center(child: Text('Giỏ hàng trống'))
                          : ListView.builder(
                              controller: controller,
                              itemCount: items.length,
                              itemBuilder: (context, i) {
                                final p = items[i];
                                final qty = _cart[p.id] ?? 0;
                                return _buildCartItemTile(
                                  p,
                                  qty,
                                  modalSetState,
                                ); // Tách Cart Item
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    _buildCheckoutButton(items.isEmpty), // Tách Checkout Button
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Tách Cart Item Tile
  Widget _buildCartItemTile(Product p, int qty, StateSetter modalSetState) {
    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildProductImage(p),
        ),
      ),
      title: Text(p.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Decrement
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () {
              modalSetState(() {
                final cur = _cart[p.id] ?? 0;
                if (cur <= 1) {
                  _cart.remove(p.id);
                } else {
                  _cart[p.id] = cur - 1;
                }
              });
              setState(() {});
              Future.microtask(() => _persistCart());
            },
          ),
          Text(qty.toString()),
          // Increment - chỉ khi còn trong kho
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {
              // Nếu đã đạt giới hạn tồn kho, không cho tăng
              if ((qty + 1) > p.stockQuantity) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Không thể tăng số lượng. Chỉ còn ${p.stockQuantity} của ${p.name} trong kho.',
                    ),
                  ),
                );
                return;
              }
              modalSetState(() {
                _cart.update(p.id, (v) => v + 1, ifAbsent: () => 1);
              });
              setState(() {});
              Future.microtask(() => _persistCart());
            },
          ),
          // Delete
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () async {
              final confirm = await _showDeleteConfirmation(context, p.name);
              if (confirm == true) {
                modalSetState(() {
                  _cart.remove(p.id);
                });
                setState(() {});
                Future.microtask(() => _persistCart());
              }
            },
          ),
        ],
      ),
    );
  }

  // Tách Checkout Button
  Widget _buildCheckoutButton(bool cartIsEmpty) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: cartIsEmpty
                ? null
                : () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CheckoutScreen(
                          cart: Map.from(_cart),
                          role: widget.role,
                          onCheckoutComplete: () async {
                            setState(() => _cart.clear());
                            await _persistCart();
                          },
                        ),
                      ),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade400,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: const Text(
              'Thanh toán',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // Tách Dialog Xác nhận xoá
  Future<bool?> _showDeleteConfirmation(
    BuildContext context,
    String productName,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Xác nhận xoá'),
        content: Text(
          'Bạn có chắc muốn xoá "$productName" khỏi giỏ hàng không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
  }
}

// --- WIDGET ĐỘC LẬP DÙNG CONST ---

// 1. Banner quảng cáo
class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/banner.png',
        width: double.infinity,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => Container(
          height: 100,
          color: Colors.orange.shade50,
          alignment: Alignment.center,
          child: const Text('Banner'),
        ),
      ),
    );
  }
}

// 2. Loading Indicator ở cuối danh sách
class _LoadingFooter extends StatelessWidget {
  const _LoadingFooter();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20.0),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

// 3. Thông báo không tìm thấy sản phẩm
class _NoProductsFound extends StatelessWidget {
  const _NoProductsFound();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24.0),
      child: Center(child: Text('Không có sản phẩm')),
    );
  }
}

// 4. Thanh kéo của Modal
class _ModalDragHandle extends StatelessWidget {
  const _ModalDragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
