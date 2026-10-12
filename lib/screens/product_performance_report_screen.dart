import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../utils/product_asset_resolver.dart';
import '../utils/type_converters.dart';

enum _PerformanceRange { today, sevenDays, thirtyDays, month }

enum _TopProductMode { quantity, revenue }

class ProductPerformanceReportScreen extends StatefulWidget {
  const ProductPerformanceReportScreen({super.key});

  @override
  State<ProductPerformanceReportScreen> createState() =>
      _ProductPerformanceReportScreenState();
}

class _ProductPerformanceReportScreenState
    extends State<ProductPerformanceReportScreen> {
  static const Color _surface = Color(0xFFF5F7FA);
  static const Color _primary = Color(0xFF146C43);
  static const Color _bestSeller = Color(0xFFFF6B00);
  static const Color _bestSellerDark = Color(0xFFC2410C);

  late Future<Map<String, dynamic>> _future;
  _PerformanceRange _range = _PerformanceRange.thirtyDays;
  _TopProductMode _topProductMode = _TopProductMode.quantity;
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _future = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final rawUserId = DBService.settings().get('current_user_id');
    final adminUserId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '');
    if (adminUserId == null) {
      throw ApiException('Thiếu thông tin admin');
    }

    debugPrint(
      '[performance] load dashboard range=$_rangeApiValue month=${_range == _PerformanceRange.month ? _monthKey(_selectedMonth) : '-'}',
    );
    try {
      final data = await ApiService.fetchProductPerformanceDashboard(
        adminUserId,
        range: _rangeApiValue,
        month: _range == _PerformanceRange.month
            ? _monthKey(_selectedMonth)
            : null,
      );
      debugPrint('[performance] dashboard api ok keys=${data.keys.join(',')}');
      return _normalizeDashboardDates(data);
    } catch (error) {
      debugPrint('[performance] dashboard api failed: $error');
      return _loadLegacyDashboard(adminUserId);
    }
  }

  Future<Map<String, dynamic>> _loadLegacyDashboard(int adminUserId) async {
    debugPrint('[performance] fallback to legacy report APIs');
    final results = await Future.wait([
      ApiService.fetchRevenueReport(adminUserId),
      ApiService.fetchProductPerformanceReport(adminUserId),
    ]);
    final revenue = results[0] as Map<String, dynamic>;
    final products = (results[1] as List<Map<String, dynamic>>)
        .map((product) => Map<String, dynamic>.from(product))
        .toList();
    final orders = await _fetchFilteredOrderDetails();
    final periodProducts = _productsFromOrders(products, orders);
    final sourceProducts = periodProducts.isEmpty ? products : periodProducts;

    sourceProducts.sort((a, b) {
      final bySold = _toInt(
        b['total_quantity_sold'],
      ).compareTo(_toInt(a['total_quantity_sold']));
      if (bySold != 0) return bySold;
      return _toDouble(
        b['total_revenue'],
      ).compareTo(_toDouble(a['total_revenue']));
    });

    final topProducts = sourceProducts
        .where((product) => _toInt(product['total_quantity_sold']) > 0)
        .take(10)
        .toList();
    final topRevenueProducts =
        sourceProducts
            .where((product) => _toDouble(product['total_revenue']) > 0)
            .toList()
          ..sort(
            (a, b) => _toDouble(
              b['total_revenue'],
            ).compareTo(_toDouble(a['total_revenue'])),
          );
    final highStockProducts =
        sourceProducts
            .where((product) => _toInt(product['current_stock']) > 50)
            .toList()
          ..sort(
            (a, b) => _toInt(
              b['current_stock'],
            ).compareTo(_toInt(a['current_stock'])),
          );
    final slowProducts = sourceProducts
        .where((product) => _toInt(product['total_quantity_sold']) < 5)
        .map((product) {
          product['days_without_order'] ??= 999;
          return product;
        })
        .take(10)
        .toList();
    final totalStock = products.fold<int>(
      0,
      (sum, product) => sum + _toInt(product['current_stock']),
    );
    final revenueChart = orders.isEmpty
        ? _filterLegacyRevenueRows(_list(revenue['revenue_by_time']))
        : _chartFromOrders(orders);
    final periodRevenue = orders.isEmpty
        ? revenueChart.fold<double>(
            0,
            (sum, row) => sum + _toDouble(row['revenue']),
          )
        : orders.fold<double>(0, (sum, order) => sum + order.totalAmount);
    final periodSold = orders.fold<int>(
      0,
      (sum, order) =>
          sum +
          order.items.fold<int>(0, (itemSum, item) => itemSum + item.quantity),
    );

    return {
      'filter': {
        'range': _rangeApiValue,
        'month': _range == _PerformanceRange.month
            ? _monthKey(_selectedMonth)
            : null,
        'source': 'legacy_reports',
      },
      'overview': {
        'total_revenue': periodRevenue,
        'total_orders': orders.isEmpty
            ? _estimateOrders(revenueChart)
            : orders.length,
        'total_products_sold': orders.isEmpty
            ? _toInt(revenue['total_products_sold'])
            : periodSold,
        'total_stock': totalStock,
        'average_order_value': orders.isEmpty || periodRevenue <= 0
            ? _toDouble(revenue['average_order_value'])
            : periodRevenue / orders.length,
      },
      'top_products': topProducts,
      'top_revenue_products': topRevenueProducts.take(10).toList(),
      'high_stock_products': highStockProducts.take(10).toList(),
      'slow_products': slowProducts,
      'suggestions': _buildLocalSuggestions(
        topProducts,
        highStockProducts,
        slowProducts,
      ),
      'revenue_chart': revenueChart,
    };
  }

  Future<List<Order>> _fetchFilteredOrderDetails() async {
    try {
      final orders = await ApiService.fetchOrders();
      final filtered = orders.where(_isOrderInSelectedRange).toList();
      final detailed = await Future.wait(
        filtered.map((order) => ApiService.fetchOrderDetail(order.id)),
      );
      return detailed.where((order) => order.items.isNotEmpty).toList();
    } catch (error) {
      debugPrint('[performance] legacy order detail fallback failed: $error');
      return const [];
    }
  }

  bool _isOrderInSelectedRange(Order order) {
    final local = order.orderDate.toLocal();
    final date = DateTime(local.year, local.month, local.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_range) {
      case _PerformanceRange.today:
        return date.isAtSameMomentAs(today);
      case _PerformanceRange.sevenDays:
        final start = today.subtract(const Duration(days: 6));
        return !date.isBefore(start) && !date.isAfter(today);
      case _PerformanceRange.thirtyDays:
        final start = today.subtract(const Duration(days: 29));
        return !date.isBefore(start) && !date.isAfter(today);
      case _PerformanceRange.month:
        return date.year == _selectedMonth.year &&
            date.month == _selectedMonth.month;
    }
  }

  List<Map<String, dynamic>> _productsFromOrders(
    List<Map<String, dynamic>> allProducts,
    List<Order> orders,
  ) {
    final byId = <String, Map<String, dynamic>>{
      for (final product in allProducts)
        (product['product_id'] ?? product['id'] ?? '').toString():
            Map<String, dynamic>.from(product),
    };
    final result = <String, Map<String, dynamic>>{};
    for (final product in allProducts) {
      final clone = Map<String, dynamic>.from(product);
      clone['total_quantity_sold'] = 0;
      clone['total_revenue'] = 0;
      clone['orders_count'] = 0;
      clone['days_without_order'] = 999;
      result[(clone['product_id'] ?? clone['id'] ?? '').toString()] = clone;
    }

    final productOrderIds = <String, Set<String>>{};
    final lastSoldAt = <String, DateTime>{};
    for (final order in orders) {
      for (final item in order.items) {
        final product =
            result[item.productId] ??
            Map<String, dynamic>.from(byId[item.productId] ?? const {});
        product['product_id'] ??= item.productId;
        product['product_name'] = (product['product_name'] ?? item.productName)
            .toString();
        product['total_quantity_sold'] =
            _toInt(product['total_quantity_sold']) + item.quantity;
        product['total_revenue'] =
            _toDouble(product['total_revenue']) +
            item.quantity * item.pricePerUnit;
        result[item.productId] = product;
        productOrderIds
            .putIfAbsent(item.productId, () => <String>{})
            .add(order.id);
        final currentLast = lastSoldAt[item.productId];
        if (currentLast == null || order.orderDate.isAfter(currentLast)) {
          lastSoldAt[item.productId] = order.orderDate;
        }
      }
    }

    final now = DateTime.now();
    for (final entry in result.entries) {
      entry.value['orders_count'] = productOrderIds[entry.key]?.length ?? 0;
      final last = lastSoldAt[entry.key];
      entry.value['days_without_order'] = last == null
          ? 999
          : now.difference(last).inDays;
    }
    return result.values.toList();
  }

  List<Map<String, dynamic>> _chartFromOrders(List<Order> orders) {
    final buckets = <String, Map<String, dynamic>>{};
    for (final order in orders) {
      final key = TypeConverters.localDateKey(order.orderDate);
      final bucket = buckets.putIfAbsent(
        key,
        () => {'period': key, 'revenue': 0.0, 'orders_count': 0},
      );
      bucket['revenue'] = _toDouble(bucket['revenue']) + order.totalAmount;
      bucket['orders_count'] = _toInt(bucket['orders_count']) + 1;
    }
    final rows = buckets.values.toList()
      ..sort(
        (a, b) => a['period'].toString().compareTo(b['period'].toString()),
      );
    return rows;
  }

  List<Map<String, dynamic>> _filterLegacyRevenueRows(
    List<Map<String, dynamic>> rows,
  ) {
    return rows.where((row) {
      final raw = row['period'];
      final date = TypeConverters.toLocalDateTime(raw);
      if (date == null) return true;
      return _isOrderInSelectedRange(
        Order(
          id: '',
          orderDate: date,
          totalAmount: _toDouble(row['revenue']),
          customerName: '',
          status: '',
          items: const [],
        ),
      );
    }).toList();
  }

  int _estimateOrders(List<Map<String, dynamic>> rows) {
    return rows.fold<int>(0, (sum, row) => sum + _toInt(row['orders_count']));
  }

  List<Map<String, dynamic>> _buildLocalSuggestions(
    List<Map<String, dynamic>> topProducts,
    List<Map<String, dynamic>> highStockProducts,
    List<Map<String, dynamic>> slowProducts,
  ) {
    final suggestions = <Map<String, dynamic>>[];
    for (final product in slowProducts.take(3)) {
      if (_toInt(product['current_stock']) >= 50) {
        suggestions.add({
          'title': '${_productName(product)} tồn kho cao nhưng bán chậm',
          'message':
              'Nên tạo voucher hoặc chương trình xả kho cho sản phẩm này.',
          'severity': 'warning',
        });
      }
    }
    for (final product in topProducts.take(3)) {
      if (_toInt(product['current_stock']) <=
          (_toInt(product['min_stock']) == 0
              ? 10
              : _toInt(product['min_stock']))) {
        suggestions.add({
          'title': '${_productName(product)} đang bán tốt, nên nhập thêm hàng',
          'message': 'Sản phẩm có doanh số cao và tồn kho đang thấp.',
          'severity': 'success',
        });
      }
    }
    if (suggestions.isEmpty) {
      suggestions.add({
        'title': 'Hiệu suất sản phẩm đang ổn định',
        'message':
            'Chưa phát hiện sản phẩm cần xử lý gấp theo tồn kho và doanh số.',
        'severity': 'info',
      });
    }
    return suggestions;
  }

  String get _rangeApiValue {
    switch (_range) {
      case _PerformanceRange.today:
        return 'today';
      case _PerformanceRange.sevenDays:
        return '7days';
      case _PerformanceRange.thirtyDays:
        return '30days';
      case _PerformanceRange.month:
        return 'month';
    }
  }

  void _reload() {
    setState(() {
      _future = _loadData();
    });
  }

  void _setRange(_PerformanceRange value) {
    setState(() {
      _range = value;
      _future = _loadData();
    });
  }

  void _setTopProductMode(_TopProductMode value) {
    setState(() {
      _topProductMode = value;
    });
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + offset,
      );
      _range = _PerformanceRange.month;
      _future = _loadData();
    });
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<Map<String, dynamic>> _list(dynamic value) {
    return ((value as List?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static String _monthKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _normalizeDashboardDates(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    final chart = _list(normalized['revenue_chart']);
    if (chart.isNotEmpty) {
      normalized['revenue_chart'] = chart.map((row) {
        final copy = Map<String, dynamic>.from(row);
        copy['period'] =
            TypeConverters.localDateKeyFromValue(copy['period']) ??
            copy['period'];
        return copy;
      }).toList();
    }
    return normalized;
  }

  String _productName(Map<String, dynamic> product) {
    final name = (product['product_name'] ?? '').toString().trim();
    return name.isEmpty ? 'Sản phẩm chưa đặt tên' : name;
  }

  Widget _buildFilterBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_PerformanceRange>(
            showSelectedIcon: false,
            selected: {_range},
            onSelectionChanged: (value) => _setRange(value.first),
            segments: const [
              ButtonSegment(
                value: _PerformanceRange.today,
                icon: Icon(Icons.today_outlined),
                label: Text('Hôm nay'),
              ),
              ButtonSegment(
                value: _PerformanceRange.sevenDays,
                icon: Icon(Icons.date_range_outlined),
                label: Text('7 ngày'),
              ),
              ButtonSegment(
                value: _PerformanceRange.thirtyDays,
                icon: Icon(Icons.calendar_view_week_outlined),
                label: Text('30 ngày'),
              ),
              ButtonSegment(
                value: _PerformanceRange.month,
                icon: Icon(Icons.calendar_month_outlined),
                label: Text('Theo tháng'),
              ),
            ],
          ),
        ),
        if (_range == _PerformanceRange.month) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Tháng trước',
              ),
              Expanded(
                child: Text(
                  'Tháng ${_selectedMonth.month}/${_selectedMonth.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Tháng sau',
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTopProductList(
    List<Map<String, dynamic>> topProducts,
    List<Map<String, dynamic>> topRevenueProducts,
  ) {
    final products = _topProductMode == _TopProductMode.quantity
        ? topProducts
        : topRevenueProducts;
    final title = _topProductMode == _TopProductMode.quantity
        ? 'Bán chạy'
        : 'Bán nhiều tiền';

    final isBestSellerMode = _topProductMode == _TopProductMode.quantity;

    return _SectionCard(
      title: 'Danh sách sản phẩm',
      borderColor: isBestSellerMode
          ? _bestSeller.withValues(alpha: 0.38)
          : Colors.grey.shade200,
      gradient: isBestSellerMode
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF7ED), Color(0xFFFFFBEB), Colors.white],
            )
          : null,
      boxShadow: isBestSellerMode
          ? [
              BoxShadow(
                color: _bestSeller.withValues(alpha: 0.16),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
      trailing: _StatusBadge(
        label: isBestSellerMode ? 'TOP BÁN CHẠY' : title,
        color: isBestSellerMode ? _bestSellerDark : _primary,
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_TopProductMode>(
              showSelectedIcon: false,
              selected: {_topProductMode},
              onSelectionChanged: (value) => _setTopProductMode(value.first),
              segments: const [
                ButtonSegment(
                  value: _TopProductMode.quantity,
                  icon: Icon(Icons.shopping_bag_outlined),
                  label: Text('Bán chạy'),
                ),
                ButtonSegment(
                  value: _TopProductMode.revenue,
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Bán nhiều tiền'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (products.isEmpty)
            const _EmptyState(
              icon: Icons.insights_outlined,
              message: 'Chưa có sản phẩm phát sinh bán trong kỳ này.',
            )
          else
            Column(
              children: products.take(10).toList().asMap().entries.map((entry) {
                return _SalesProductTile(
                  rank: entry.key + 1,
                  product: entry.value,
                  name: _productName(entry.value),
                  mode: _topProductMode,
                  onTap: () => _openDetail(entry.value, entry.key + 1),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildHighStock(List<Map<String, dynamic>> products) {
    return _SectionCard(
      title: 'Sản phẩm tồn kho cao',
      trailing: const _StatusBadge(label: 'Ngưỡng > 50', color: Colors.orange),
      child: products.isEmpty
          ? const _EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'Không có sản phẩm tồn kho cao.',
            )
          : Column(
              children: products
                  .take(8)
                  .map(
                    (product) => _AlertProductTile(
                      product: product,
                      name: _productName(product),
                      badge: 'Tồn cao',
                      badgeColor: Colors.orange,
                      titleValue: 'Tồn ${_toInt(product['current_stock'])}',
                      subtitle:
                          'Đã bán ${_toInt(product['total_quantity_sold'])}',
                      onTap: () => _openDetail(product, null),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildSlowProducts(List<Map<String, dynamic>> products) {
    return _SectionCard(
      title: 'Sản phẩm bán chậm',
      trailing: const _StatusBadge(label: 'Sold < 5', color: Colors.red),
      child: products.isEmpty
          ? const _EmptyState(
              icon: Icons.speed_outlined,
              message: 'Không có sản phẩm bán chậm trong kỳ này.',
            )
          : Column(
              children: products
                  .take(8)
                  .map(
                    (product) => _AlertProductTile(
                      product: product,
                      name: _productName(product),
                      badge: _slowBadge(product),
                      badgeColor: Colors.red,
                      titleValue:
                          'Đã bán ${_toInt(product['total_quantity_sold'])}',
                      subtitle:
                          '${_toInt(product['days_without_order'])} ngày chưa phát sinh đơn',
                      onTap: () => _openDetail(product, null),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  String _slowBadge(Map<String, dynamic> product) {
    final stock = _toInt(product['current_stock']);
    if (stock > 50) return 'Cần xả kho';
    if (stock > 20) return 'Nên giảm giá';
    return 'Bán chậm';
  }

  Widget _buildSuggestions(List<Map<String, dynamic>> suggestions) {
    return _SectionCard(
      title: 'Đề xuất thông minh',
      child: suggestions.isEmpty
          ? const _EmptyState(
              icon: Icons.lightbulb_outline,
              message: 'Chưa có đề xuất trong kỳ này.',
            )
          : Column(
              children: suggestions
                  .map(
                    (item) => _SuggestionTile(
                      title: (item['title'] ?? '').toString(),
                      message: (item['message'] ?? '').toString(),
                      severity: (item['severity'] ?? 'info').toString(),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  void _openDetail(Map<String, dynamic> product, int? rank) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _ProductPerformanceDetailScreen(product: product, rank: rank),
      ),
    );
  }

  Widget _buildError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 42),
            const SizedBox(height: 12),
            Text(
              error is ApiException
                  ? error.message
                  : 'Không tải được dashboard hiệu suất sản phẩm',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text('Hiệu suất sản phẩm'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _buildError(snapshot.error!);

          final data = snapshot.data ?? const <String, dynamic>{};
          final topProducts = _list(data['top_products']);
          final topRevenueProducts = _list(data['top_revenue_products']);
          final highStock = _list(data['high_stock_products']);
          final slowProducts = _list(data['slow_products']);
          final suggestions = _list(data['suggestions']);
          if (topRevenueProducts.isEmpty && topProducts.isNotEmpty) {
            topRevenueProducts.addAll(
              List<Map<String, dynamic>>.from(topProducts)..sort(
                (a, b) => _toDouble(
                  b['total_revenue'],
                ).compareTo(_toDouble(a['total_revenue'])),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _SectionCard(
                  title: 'Bộ lọc thời gian',
                  child: _buildFilterBar(),
                ),
                const SizedBox(height: 14),
                _buildTopProductList(topProducts, topRevenueProducts),
                const SizedBox(height: 14),
                _buildHighStock(highStock),
                const SizedBox(height: 14),
                _buildSlowProducts(slowProducts),
                const SizedBox(height: 14),
                _buildSuggestions(suggestions),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProductPerformanceDetailScreen extends StatelessWidget {
  final Map<String, dynamic> product;
  final int? rank;

  const _ProductPerformanceDetailScreen({required this.product, this.rank});

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _formatCurrency(num amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} VNĐ';
  }

  String _productName() {
    final name = (product['product_name'] ?? '').toString().trim();
    return name.isEmpty ? 'Sản phẩm chưa đặt tên' : name;
  }

  @override
  Widget build(BuildContext context) {
    final sold = _toInt(product['total_quantity_sold']);
    final revenue = _toDouble(product['total_revenue']);
    final stock = _toInt(product['current_stock']);
    final ordersCount = _toInt(product['orders_count']);
    final unit = (product['unit'] ?? 'sp').toString();
    final salePrice = _toDouble(product['sale_price'] ?? product['price']);
    final daysWithoutOrder = _toInt(product['days_without_order']);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Chi tiết sản phẩm'),
        backgroundColor: const Color(0xFF146C43),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              child: _ProductThumb(product: product, size: double.infinity),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rank != null) ...[
                _RankBadge(rank: rank!),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _productName(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${product['category_name'] ?? 'Chưa phân loại'} • ${product['barcode'] ?? 'Chưa có mã'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final ratio = constraints.maxWidth < 380 ? 1.35 : 1.8;
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: ratio,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  _MetricCard(
                    title: 'Đã bán',
                    value: '$sold $unit',
                    subtitle: 'Trong kỳ lọc',
                    icon: Icons.shopping_bag_outlined,
                    color: const Color(0xFF146C43),
                  ),
                  _MetricCard(
                    title: 'Doanh thu',
                    value: _formatCurrency(revenue),
                    subtitle: '$ordersCount đơn hàng',
                    icon: Icons.payments_outlined,
                    color: Colors.orange.shade700,
                  ),
                  _MetricCard(
                    title: 'Tồn kho',
                    value: '$stock $unit',
                    subtitle: 'Hiện tại',
                    icon: Icons.warehouse_outlined,
                    color: Colors.blueGrey,
                  ),
                  _MetricCard(
                    title: 'Giá bán',
                    value: salePrice <= 0
                        ? 'Chưa có'
                        : _formatCurrency(salePrice),
                    subtitle: 'Giá niêm yết',
                    icon: Icons.sell_outlined,
                    color: Colors.indigo,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Thông tin phân tích',
            child: Column(
              children: [
                _DetailRow('Số đơn', '$ordersCount'),
                _DetailRow('Số ngày không phát sinh đơn', '$daysWithoutOrder'),
                _DetailRow('Mã sản phẩm', '${product['product_id'] ?? '-'}'),
                _DetailRow('Mã vạch', '${product['barcode'] ?? '-'}'),
                _DetailRow('Danh mục', '${product['category_name'] ?? '-'}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final Color? borderColor;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;

  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
    this.borderColor,
    this.gradient,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gradient == null ? Colors.white : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor ?? Colors.grey.shade200),
        boxShadow: boxShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(child: trailing!),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const Spacer(),
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _SalesProductTile extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> product;
  final String name;
  final _TopProductMode mode;
  final VoidCallback onTap;

  const _SalesProductTile({
    required this.rank,
    required this.product,
    required this.name,
    required this.mode,
    required this.onTap,
  });

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatCurrency(num amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} VNĐ';
  }

  @override
  Widget build(BuildContext context) {
    final sold = _toInt(product['total_quantity_sold']);
    final revenue = _toDouble(product['total_revenue']);
    final ordersCount = _toInt(product['orders_count']);
    final titleValue = mode == _TopProductMode.quantity
        ? '$sold đã bán'
        : _formatCurrency(revenue);
    final subtitle = mode == _TopProductMode.quantity
        ? '${_formatCurrency(revenue)} · $ordersCount đơn'
        : '$sold sản phẩm · $ordersCount đơn';

    final isBestSellerMode = mode == _TopProductMode.quantity;
    final accentColor = isBestSellerMode
        ? const Color(0xFFFF6B00)
        : const Color(0xFF146C43);
    final borderColor = isBestSellerMode
        ? (rank == 1 ? const Color(0xFFFF6B00) : const Color(0xFFFDBA74))
        : Colors.grey.shade200;
    final tileGradient = isBestSellerMode
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: rank == 1
                ? const [Color(0xFFFFEDD5), Color(0xFFFFF7ED)]
                : const [Color(0xFFFFFBEB), Colors.white],
          )
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(rank == 1 && isBestSellerMode ? 12 : 10),
        decoration: BoxDecoration(
          color: tileGradient == null ? Colors.white : null,
          gradient: tileGradient,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: rank == 1 && isBestSellerMode ? 1.6 : 1,
          ),
          boxShadow: isBestSellerMode && rank <= 3
              ? [
                  BoxShadow(
                    color: accentColor.withValues(
                      alpha: rank == 1 ? 0.18 : 0.1,
                    ),
                    blurRadius: rank == 1 ? 18 : 10,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            _RankBadge(
              rank: rank,
              color: accentColor,
              featured: isBestSellerMode,
            ),
            const SizedBox(width: 10),
            _ProductThumb(
              product: product,
              size: rank == 1 && isBestSellerMode ? 56 : 50,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (isBestSellerMode && rank <= 3) ...[
                        const SizedBox(width: 6),
                        _StatusBadge(
                          label: rank == 1 ? 'HOT NHẤT' : 'BÁN CHẠY',
                          color: accentColor,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                titleValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: isBestSellerMode
                      ? const Color(0xFFC2410C)
                      : Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final String name;
  final String badge;
  final Color badgeColor;
  final String titleValue;
  final String subtitle;
  final VoidCallback onTap;

  const _AlertProductTile({
    required this.product,
    required this.name,
    required this.badge,
    required this.badgeColor,
    required this.titleValue,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: badgeColor.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            _ProductThumb(product: product, size: 50),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusBadge(label: badge, color: badgeColor),
                const SizedBox(height: 6),
                Text(
                  titleValue,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final String title;
  final String message;
  final String severity;

  const _SuggestionTile({
    required this.title,
    required this.message,
    required this.severity,
  });

  Color get _color {
    switch (severity) {
      case 'success':
        return const Color(0xFF146C43);
      case 'warning':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  IconData get _icon {
    switch (severity) {
      case 'success':
        return Icons.trending_up_outlined;
      case 'warning':
        return Icons.warning_amber_outlined;
      default:
        return Icons.lightbulb_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: _color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(message, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  final Map<String, dynamic> product;
  final double size;

  const _ProductThumb({required this.product, required this.size});

  @override
  Widget build(BuildContext context) {
    final imageUrl = (product['image_url'] ?? '').toString();
    final resolvedUrl = imageUrl.startsWith('/')
        ? '${ApiService.baseUrl}$imageUrl'
        : imageUrl;
    final fallbackAsset = ProductAssetResolver.forMap(product);
    final fallback = Image.asset(
      fallbackAsset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        ProductAssetResolver.defaultProductAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl.startsWith('assets/')
            ? fallback
            : resolvedUrl.startsWith('http')
            ? Image.network(
                resolvedUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  final Color color;
  final bool featured;

  const _RankBadge({
    required this.rank,
    this.color = const Color(0xFF146C43),
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    final isChampion = featured && rank == 1;

    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isChampion ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: featured
            ? Border.all(color: color.withValues(alpha: 0.45))
            : null,
      ),
      child: Text(
        '#$rank',
        style: TextStyle(
          color: isChampion ? Colors.white : color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: Colors.black26, size: 38),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
