import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../utils/type_converters.dart';
import 'order_list_screen.dart';

class RevenueOverviewScreen extends StatefulWidget {
  const RevenueOverviewScreen({super.key});

  @override
  State<RevenueOverviewScreen> createState() => _RevenueOverviewScreenState();
}

enum _RevenueTimeRange { today, sevenDays, thirtyDays, month }

class _RevenueOverviewScreenState extends State<RevenueOverviewScreen> {
  late Future<_RevenueDashboardData> _future;
  _DashboardTimeFilter _selectedFilter = _DashboardTimeFilter.day;
  late DateTime _visibleRevenueMonth;
  late DateTime _selectedRevenueDate;
  _RevenueTimeRange _timeRange = _RevenueTimeRange.thirtyDays;
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleRevenueMonth = DateTime(now.year, now.month);
    _selectedRevenueDate = DateTime(now.year, now.month, now.day);
    _selectedMonth = DateTime(now.year, now.month);
    _future = _loadData();
  }

  Future<_RevenueDashboardData> _loadData() async {
    final rawUserId = DBService.settings().get('current_user_id');
    final adminUserId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '');
    if (adminUserId == null) {
      throw ApiException('Thiếu thông tin admin');
    }

    var revenue = await ApiService.fetchRevenueReport(adminUserId);

    // Filter revenue data by selected time range
    try {
      final orders = await ApiService.fetchOrders();
      final filtered = orders.where(_isOrderInSelectedRange).toList();
      final detailed = await Future.wait(
        filtered.map((order) => ApiService.fetchOrderDetail(order.id)),
      );
      revenue = _calculateFilteredRevenue(revenue, detailed);
    } catch (error) {
      debugPrint('[revenue] order filtering failed: $error');
    }

    return _RevenueDashboardData(revenue: revenue);
  }

  bool _isOrderInSelectedRange(Order order) {
    final local = order.orderDate.toLocal();
    final date = DateTime(local.year, local.month, local.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_timeRange) {
      case _RevenueTimeRange.today:
        return date.isAtSameMomentAs(today);
      case _RevenueTimeRange.sevenDays:
        final start = today.subtract(const Duration(days: 6));
        return !date.isBefore(start) && !date.isAfter(today);
      case _RevenueTimeRange.thirtyDays:
        final start = today.subtract(const Duration(days: 29));
        return !date.isBefore(start) && !date.isAfter(today);
      case _RevenueTimeRange.month:
        return date.year == _selectedMonth.year &&
            date.month == _selectedMonth.month;
    }
  }

  Map<String, dynamic> _calculateFilteredRevenue(
    Map<String, dynamic> baseRevenue,
    List<Order> orders,
  ) {
    final filtered = Map<String, dynamic>.from(baseRevenue);
    double totalNetRevenue = 0; // after discount
    double totalDiscount = 0;
    double totalGrossRevenue = 0; // before discount
    int totalOrders = 0;
    int totalProductsSold = 0;
    final revenueByDate = <String, Map<String, dynamic>>{};
    final revenueByMonth = <String, Map<String, dynamic>>{};
    final revenueByYear = <String, Map<String, dynamic>>{};

    for (final order in orders) {
      totalNetRevenue += order.totalAmount;
      totalDiscount += order.discountAmount;
      final grossRevenue = order.totalAmount + order.discountAmount;
      totalGrossRevenue += grossRevenue;
      totalOrders += 1;
      totalProductsSold += order.items.fold<int>(
        0,
        (sum, item) => sum + item.quantity,
      );
      _addRevenueBucket(
        revenueByDate,
        TypeConverters.localDateKey(order.orderDate),
        grossRevenue,
      );
      final local = order.orderDate.toLocal();
      _addRevenueBucket(
        revenueByMonth,
        '${local.year}-${local.month.toString().padLeft(2, '0')}-01',
        grossRevenue,
      );
      _addRevenueBucket(revenueByYear, '${local.year}-01-01', grossRevenue);
    }

    final averageOrderValue = totalOrders > 0
        ? totalGrossRevenue / totalOrders
        : 0;

    filtered['total_revenue'] = totalGrossRevenue;
    filtered['total_orders'] = totalOrders;
    filtered['total_net_revenue'] = totalNetRevenue;
    filtered['average_order_value'] = averageOrderValue;
    filtered['total_discount'] = totalDiscount;
    filtered['total_products_sold'] = totalProductsSold;
    filtered['revenue_by_time'] = _sortedRevenueBuckets(revenueByDate);
    filtered['revenue_by_month'] = _sortedRevenueBuckets(revenueByMonth);
    filtered['revenue_by_year'] = _sortedRevenueBuckets(revenueByYear);

    return filtered;
  }

  void _addRevenueBucket(
    Map<String, Map<String, dynamic>> buckets,
    String period,
    double revenue,
  ) {
    final bucket = buckets.putIfAbsent(
      period,
      () => {'period': period, 'revenue': 0.0, 'orders_count': 0},
    );
    bucket['revenue'] = _toDouble(bucket['revenue']) + revenue;
    bucket['orders_count'] = _toInt(bucket['orders_count']) + 1;
  }

  List<Map<String, dynamic>> _sortedRevenueBuckets(
    Map<String, Map<String, dynamic>> buckets,
  ) {
    return buckets.values.toList()..sort(
      (a, b) => a['period'].toString().compareTo(b['period'].toString()),
    );
  }

  void _reload() {
    setState(() {
      _future = _loadData();
    });
  }

  void _setTimeRange(_RevenueTimeRange value) {
    setState(() {
      _timeRange = value;
      _future = _loadData();
    });
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + offset,
      );
      _timeRange = _RevenueTimeRange.month;
      _future = _loadData();
    });
  }

  void _changeRevenueMonth(int monthOffset) {
    setState(() {
      _visibleRevenueMonth = DateTime(
        _visibleRevenueMonth.year,
        _visibleRevenueMonth.month + monthOffset,
      );
      _selectedRevenueDate = DateTime(
        _visibleRevenueMonth.year,
        _visibleRevenueMonth.month,
        1,
      );
    });
  }

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
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ';
  }

  String _compactCurrency(num value) {
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)} tỷ';
    }
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)} tr';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}k';
    }
    return value.round().toString();
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
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
                if (onTap != null)
                  Icon(Icons.chevron_right, color: Colors.grey.shade500),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKpiGrid(Map<String, dynamic> revenue) {
    final totalRevenue = _toDouble(revenue['total_revenue']);
    final netRevenue = _toDouble(
      revenue['total_net_revenue'] ?? revenue['total_revenue'],
    );
    final totalOrders = _toInt(revenue['total_orders']);
    final averageOrderValue = _toDouble(revenue['average_order_value']);
    final totalDiscount = _toDouble(revenue['total_discount']);
    final totalProfit = revenue['total_profit'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final childAspectRatio = width < 380
            ? 1.05
            : width < 520
            ? 1.18
            : 1.45;

        return GridView.count(
          crossAxisCount: 2,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildKpiCard(
              title: 'Tổng doanh thu',
              value: _formatCurrency(totalRevenue),
              subtitle: 'Doanh thu trước giảm giá',
              icon: Icons.payments_outlined,
              color: Colors.indigo,
            ),
            _buildKpiCard(
              title: 'Tổng số đơn hàng',
              value: '$totalOrders',
              subtitle: 'Đơn đã thanh toán/hoàn thành',
              icon: Icons.receipt_long_outlined,
              color: Colors.green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OrderListScreen()),
                );
              },
            ),
            _buildKpiCard(
              title: 'Giá trị trung bình/đơn',
              value: _formatCurrency(averageOrderValue),
              subtitle: 'Theo doanh thu thuần',
              icon: Icons.trending_up_outlined,
              color: Colors.orange,
            ),
            _buildKpiCard(
              title: 'Doanh thu thuần',
              value: _formatCurrency(netRevenue),
              subtitle: 'Sau giảm giá: ${_formatCurrency(totalDiscount)}',
              icon: Icons.account_balance_wallet_outlined,
              color: Colors.blue,
            ),
            if (totalProfit != null)
              _buildKpiCard(
                title: 'Tổng lợi nhuận',
                value: _formatCurrency(_toDouble(totalProfit)),
                subtitle: 'Tính theo giá nhập gần nhất',
                icon: Icons.ssid_chart_outlined,
                color: Colors.teal,
              ),
          ],
        );
      },
    );
  }

  Widget _buildFilterSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_DashboardTimeFilter>(
        segments: const [
          ButtonSegment(
            value: _DashboardTimeFilter.day,
            icon: Icon(Icons.today_outlined),
            label: Text('Ngày'),
          ),
          ButtonSegment(
            value: _DashboardTimeFilter.month,
            icon: Icon(Icons.calendar_view_month_outlined),
            label: Text('Tháng'),
          ),
          ButtonSegment(
            value: _DashboardTimeFilter.year,
            icon: Icon(Icons.event_available_outlined),
            label: Text('Năm'),
          ),
        ],
        selected: {_selectedFilter},
        showSelectedIcon: false,
        onSelectionChanged: (value) {
          setState(() {
            _selectedFilter = value.first;
          });
        },
      ),
    );
  }

  Widget _buildTimeRangeFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_RevenueTimeRange>(
            showSelectedIcon: false,
            selected: {_timeRange},
            onSelectionChanged: (value) => _setTimeRange(value.first),
            segments: const [
              ButtonSegment(
                value: _RevenueTimeRange.today,
                icon: Icon(Icons.today_outlined),
                label: Text('Hôm nay'),
              ),
              ButtonSegment(
                value: _RevenueTimeRange.sevenDays,
                icon: Icon(Icons.date_range_outlined),
                label: Text('7 ngày'),
              ),
              ButtonSegment(
                value: _RevenueTimeRange.thirtyDays,
                icon: Icon(Icons.calendar_view_week_outlined),
                label: Text('30 ngày'),
              ),
              ButtonSegment(
                value: _RevenueTimeRange.month,
                icon: Icon(Icons.calendar_month_outlined),
                label: Text('Theo tháng'),
              ),
            ],
          ),
        ),
        if (_timeRange == _RevenueTimeRange.month) ...[
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

  Widget _buildTrendSection(Map<String, dynamic> revenue) {
    if (_selectedFilter == _DashboardTimeFilter.day) {
      return _buildRevenueCalendar(revenue);
    }

    final chartData = _TrendChartData.fromApi(revenue, _selectedFilter);

    return _DashboardSection(
      title: chartData.title,
      trailing: Text(
        chartData.totalFormatted,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chartData.description,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 280,
            child: chartData.points.isEmpty
                ? const Center(child: Text('Chưa có dữ liệu doanh thu'))
                : BarChart(
                    BarChartData(
                      maxY: chartData.maxY,
                      barGroups: chartData.points.asMap().entries.map((entry) {
                        final index = entry.key;
                        final point = entry.value;
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: point.revenue,
                              width: chartData.barWidth,
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.blue.shade600,
                            ),
                          ],
                        );
                      }).toList(),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: chartData.interval,
                        getDrawingHorizontalLine: (value) =>
                            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 46,
                            interval: chartData.interval,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox.shrink();
                              return Text(
                                _compactCurrency(value),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 ||
                                  index >= chartData.points.length) {
                                return const SizedBox.shrink();
                              }
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                space: 8,
                                child: Text(
                                  chartData.points[index].label,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final point = chartData.points[groupIndex];
                            return BarTooltipItem(
                              '${point.label}\n',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              children: [
                                TextSpan(
                                  text: _formatCurrency(point.revenue),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCalendar(Map<String, dynamic> revenue) {
    final calendarData = _RevenueCalendarData.fromApi(
      revenue,
      month: _visibleRevenueMonth,
      selectedDate: _selectedRevenueDate,
    );

    return _DashboardSection(
      title: 'Quản lý doanh thu theo ngày',
      trailing: Text(
        calendarData.totalFormatted,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Tháng trước',
                onPressed: () => _changeRevenueMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Tháng ${calendarData.month}/${calendarData.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Chọn một ngày để xem biểu đồ tuần đó',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Tháng sau',
                onPressed: () => _changeRevenueMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DaySummaryPill(
                  label: 'Ngày có doanh thu',
                  value: '${calendarData.revenueDays}',
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DaySummaryPill(
                  label: 'Ngày cao nhất',
                  value: calendarData.bestDayLabel,
                  icon: Icons.trending_up,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _DaySummaryPill(
                  label: 'Trung bình/ngày',
                  value: _compactCurrency(calendarData.averageRevenue),
                  icon: Icons.insights_outlined,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DaySummaryPill(
                  label: 'Ngày đang chọn',
                  value:
                      '${calendarData.selectedDate.day}/${calendarData.selectedDate.month}',
                  icon: Icons.today_outlined,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Lịch doanh thu',
            style: TextStyle(
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              _WeekdayLabel('T2'),
              _WeekdayLabel('T3'),
              _WeekdayLabel('T4'),
              _WeekdayLabel('T5'),
              _WeekdayLabel('T6'),
              _WeekdayLabel('T7'),
              _WeekdayLabel('CN'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: calendarData.cells.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, index) {
              final cell = calendarData.cells[index];
              if (cell == null) return const SizedBox.shrink();

              final hasRevenue = cell.revenue > 0;
              final isToday = cell.isToday;
              final isSelected = cell.isSelected;
              final isSelectedWeek = cell.isSelectedWeek;

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() {
                    _selectedRevenueDate = cell.date;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blue.shade100
                        : isSelectedWeek
                        ? Colors.blue.shade50
                        : hasRevenue
                        ? Colors.green.shade50
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Colors.blue.shade700
                          : isToday
                          ? Colors.blue.shade400
                          : hasRevenue
                          ? Colors.green.shade200
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${cell.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected || isToday
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: isSelected || isToday
                              ? Colors.blue.shade800
                              : Colors.grey.shade800,
                        ),
                      ),
                      const Spacer(),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          hasRevenue ? _compactCurrency(cell.revenue) : '0',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: hasRevenue
                                ? Colors.green.shade800
                                : Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Biểu đồ tuần ${calendarData.weekRangeLabel}',
            style: TextStyle(
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 260,
            child: BarChart(
              BarChartData(
                maxY: calendarData.weekMaxY,
                barGroups: calendarData.weekPoints.asMap().entries.map((entry) {
                  final index = entry.key;
                  final point = entry.value;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: point.revenue,
                        width: 18,
                        borderRadius: BorderRadius.circular(4),
                        color: point.isSelected
                            ? Colors.blue.shade700
                            : Colors.green.shade600,
                      ),
                    ],
                  );
                }).toList(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: calendarData.weekInterval,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      interval: calendarData.weekInterval,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Text(
                          _compactCurrency(value),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 ||
                            index >= calendarData.weekPoints.length) {
                          return const SizedBox.shrink();
                        }
                        final point = calendarData.weekPoints[index];
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 8,
                          child: Text(
                            point.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: point.isSelected
                                  ? Colors.blue.shade800
                                  : Colors.black54,
                              fontWeight: point.isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final point = calendarData.weekPoints[groupIndex];
                      return BarTooltipItem(
                        '${point.label}\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        children: [
                          TextSpan(
                            text: _formatCurrency(point.revenue),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountProfitStrip(Map<String, dynamic> revenue) {
    final totalDiscount = _toDouble(revenue['total_discount']);
    final productsSold = _toInt(revenue['total_products_sold']);
    final profitNote = (revenue['profit_note'] ?? '').toString();

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemCount = profitNote.isNotEmpty ? 3 : 2;
        final itemWidth = constraints.maxWidth < 520
            ? constraints.maxWidth
            : (constraints.maxWidth - ((itemCount - 1) * 10)) / itemCount;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: itemWidth,
              child: _SmallMetric(
                label: 'Tổng giảm giá',
                value: _formatCurrency(totalDiscount),
                icon: Icons.local_offer_outlined,
                color: Colors.purple,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _SmallMetric(
                label: 'Sản phẩm đã bán',
                value: '$productsSold',
                icon: Icons.inventory_2_outlined,
                color: Colors.cyan,
              ),
            ),
            if (profitNote.isNotEmpty)
              SizedBox(
                width: itemWidth,
                child: _SmallMetric(
                  label: 'Ghi chú lợi nhuận',
                  value: 'Thiếu giá nhập',
                  icon: Icons.info_outline,
                  color: Colors.amber,
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RevenueDashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Dashboard doanh thu'),
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Dashboard doanh thu'),
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      snapshot.error is ApiException
                          ? (snapshot.error as ApiException).message
                          : 'Không tải được báo cáo',
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
            ),
          );
        }

        final data = snapshot.data!;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FB),
          appBar: AppBar(
            title: const Text('Dashboard doanh thu'),
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                tooltip: 'Tải lại',
                icon: const Icon(Icons.refresh),
                onPressed: _reload,
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tổng quan kinh doanh',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Theo dõi doanh thu, đơn hàng và sản phẩm bán chạy',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  _DashboardSection(
                    title: 'Bộ lọc kỳ báo cáo',
                    child: _buildTimeRangeFilter(),
                  ),
                  const SizedBox(height: 14),
                  _buildKpiGrid(data.revenue),
                  const SizedBox(height: 12),
                  _buildDiscountProfitStrip(data.revenue),
                  const SizedBox(height: 18),
                  _DashboardSection(
                    title: 'Bộ lọc hiển thị lịch',
                    child: _buildFilterSelector(),
                  ),
                  const SizedBox(height: 14),
                  _buildTrendSection(data.revenue),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _DashboardTimeFilter { day, month, year }

class _DashboardSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _DashboardSection({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: trailing!,
                    ),
                  ),
                ),
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

class _WeekdayLabel extends StatelessWidget {
  final String label;

  const _WeekdayLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _DaySummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _DaySummaryPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SmallMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.w800),
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
}

class _CalendarCell {
  final DateTime date;
  final int day;
  final double revenue;
  final bool isToday;
  final bool isSelected;
  final bool isSelectedWeek;

  const _CalendarCell({
    required this.date,
    required this.day,
    required this.revenue,
    required this.isToday,
    required this.isSelected,
    required this.isSelectedWeek,
  });
}

class _DailyRevenuePoint {
  final DateTime date;
  final String label;
  final int day;
  final double revenue;
  final bool isSelected;

  const _DailyRevenuePoint({
    required this.date,
    required this.label,
    required this.day,
    required this.revenue,
    required this.isSelected,
  });
}

class _RevenueCalendarData {
  final int month;
  final int year;
  final DateTime selectedDate;
  final List<_CalendarCell?> cells;
  final List<_DailyRevenuePoint> monthPoints;
  final List<_DailyRevenuePoint> weekPoints;

  const _RevenueCalendarData({
    required this.month,
    required this.year,
    required this.selectedDate,
    required this.cells,
    required this.monthPoints,
    required this.weekPoints,
  });

  double get totalRevenue =>
      monthPoints.fold(0, (sum, point) => sum + point.revenue);

  int get revenueDays => monthPoints.where((point) => point.revenue > 0).length;

  double get averageRevenue {
    if (monthPoints.isEmpty) return 0;
    return totalRevenue / monthPoints.length;
  }

  _DailyRevenuePoint? get bestDay {
    if (monthPoints.isEmpty) return null;
    return monthPoints.reduce(
      (best, point) => point.revenue > best.revenue ? point : best,
    );
  }

  String get bestDayLabel {
    final day = bestDay;
    if (day == null || day.revenue <= 0) return 'Chưa có';
    return day.label;
  }

  String get weekRangeLabel {
    if (weekPoints.isEmpty) return '';
    final start = weekPoints.first.date;
    final end = weekPoints.last.date;
    return '${start.day}/${start.month} - ${end.day}/${end.month}';
  }

  double get weekMaxY {
    final highest = weekPoints.fold<double>(
      0,
      (max, point) => point.revenue > max ? point.revenue : max,
    );
    if (highest <= 0) return 1;
    return highest * 1.2;
  }

  double get weekInterval {
    final value = weekMaxY / 4;
    return value <= 0 ? 1 : value;
  }

  String get totalFormatted =>
      '${totalRevenue.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';

  factory _RevenueCalendarData.fromApi(
    Map<String, dynamic> api, {
    required DateTime month,
    required DateTime selectedDate,
  }) {
    final today = DateTime.now();
    final visibleMonth = DateTime(month.year, month.month);
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final lastDay = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final normalizedSelected = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final weekStart = normalizedSelected.subtract(
      Duration(days: normalizedSelected.weekday - 1),
    );
    final weekEnd = weekStart.add(const Duration(days: 6));
    final revenueByDate = _TrendChartData.dailyRevenueMap(api);
    final cells = <_CalendarCell?>[];
    final monthPoints = <_DailyRevenuePoint>[];

    for (var i = 1; i < firstDay.weekday; i++) {
      cells.add(null);
    }

    for (var day = 1; day <= lastDay; day++) {
      final date = DateTime(visibleMonth.year, visibleMonth.month, day);
      final revenue = revenueByDate[_TrendChartData.dateKey(date)] ?? 0;
      final isToday = _isSameDate(date, today);
      final isSelected = _isSameDate(date, normalizedSelected);
      final isSelectedWeek =
          !date.isBefore(weekStart) && !date.isAfter(weekEnd);

      monthPoints.add(
        _DailyRevenuePoint(
          date: date,
          label: _weekdayDateLabel(date),
          day: day,
          revenue: revenue,
          isSelected: isSelected,
        ),
      );
      cells.add(
        _CalendarCell(
          date: date,
          day: day,
          revenue: revenue,
          isToday: isToday,
          isSelected: isSelected,
          isSelectedWeek: isSelectedWeek,
        ),
      );
    }

    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    final weekPoints = List.generate(7, (index) {
      final date = weekStart.add(Duration(days: index));
      return _DailyRevenuePoint(
        date: date,
        label: _weekdayDateLabel(date),
        day: date.day,
        revenue: revenueByDate[_TrendChartData.dateKey(date)] ?? 0,
        isSelected: _isSameDate(date, normalizedSelected),
      );
    });

    return _RevenueCalendarData(
      month: visibleMonth.month,
      year: visibleMonth.year,
      selectedDate: normalizedSelected,
      cells: cells,
      monthPoints: monthPoints,
      weekPoints: weekPoints,
    );
  }

  static bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _weekdayDateLabel(DateTime date) {
    const weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return '${weekdays[date.weekday - 1]}\n${date.day}/${date.month}';
  }
}

class _TrendPoint {
  final String label;
  final double revenue;

  const _TrendPoint({required this.label, required this.revenue});
}

class _TrendChartData {
  final List<_TrendPoint> points;
  final _DashboardTimeFilter filter;

  const _TrendChartData({required this.points, required this.filter});

  String get title {
    switch (filter) {
      case _DashboardTimeFilter.day:
        return 'Lịch doanh thu theo ngày';
      case _DashboardTimeFilter.month:
        return 'Biểu đồ doanh thu theo tháng';
      case _DashboardTimeFilter.year:
        return 'Biểu đồ doanh thu theo năm';
    }
  }

  String get description {
    switch (filter) {
      case _DashboardTimeFilter.day:
        return 'Doanh thu từng ngày trong tháng hiện tại';
      case _DashboardTimeFilter.month:
        return 'Doanh thu 12 tháng trong năm hiện tại';
      case _DashboardTimeFilter.year:
        return 'Doanh thu theo từng năm có dữ liệu';
    }
  }

  double get totalRevenue =>
      points.fold(0, (sum, point) => sum + point.revenue);

  String get totalFormatted =>
      '${totalRevenue.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';

  double get maxY {
    final highest = points.fold<double>(
      0,
      (max, point) => point.revenue > max ? point.revenue : max,
    );
    if (highest <= 0) return 1;
    return highest * 1.2;
  }

  double get interval {
    final value = maxY / 4;
    return value <= 0 ? 1 : value;
  }

  double get barWidth {
    switch (filter) {
      case _DashboardTimeFilter.day:
        return 10;
      case _DashboardTimeFilter.month:
        return 12;
      case _DashboardTimeFilter.year:
        return 22;
    }
  }

  factory _TrendChartData.fromApi(
    Map<String, dynamic> api,
    _DashboardTimeFilter filter,
  ) {
    switch (filter) {
      case _DashboardTimeFilter.day:
        return _TrendChartData(points: const [], filter: filter);
      case _DashboardTimeFilter.month:
        return _TrendChartData(
          points: _currentYearMonthPoints(api),
          filter: filter,
        );
      case _DashboardTimeFilter.year:
        return _TrendChartData(points: _yearPoints(api), filter: filter);
    }
  }

  static List<_TrendPoint> _currentYearMonthPoints(Map<String, dynamic> api) {
    final revenueByMonth = monthlyRevenueMap(api);
    final year = DateTime.now().year;
    return List.generate(12, (index) {
      final month = index + 1;
      return _TrendPoint(
        label: 'T$month',
        revenue: revenueByMonth[monthKey(year, month)] ?? 0,
      );
    });
  }

  static List<_TrendPoint> _yearPoints(Map<String, dynamic> api) {
    final rows = (api['revenue_by_year'] as List?) ?? const [];
    final points = rows.whereType<Map>().map((row) {
      final period = row['period']?.toString() ?? '';
      final year = period.length >= 4 ? period.substring(0, 4) : period;
      return _TrendPoint(label: year, revenue: toDoubleValue(row['revenue']));
    }).toList();

    points.sort((a, b) => a.label.compareTo(b.label));
    return points;
  }

  static Map<String, double> dailyRevenueMap(Map<String, dynamic> api) {
    final rows = (api['revenue_by_time'] as List?) ?? const [];
    final result = <String, double>{};
    for (final row in rows.whereType<Map>()) {
      final key = TypeConverters.localDateKeyFromValue(row['period']);
      if (key == null) continue;
      result[key] = (result[key] ?? 0) + toDoubleValue(row['revenue']);
    }
    return result;
  }

  static Map<String, double> monthlyRevenueMap(Map<String, dynamic> api) {
    final rows = (api['revenue_by_month'] as List?) ?? const [];
    final result = <String, double>{};
    for (final row in rows.whereType<Map>()) {
      final key = TypeConverters.localDateKeyFromValue(row['period']);
      if (key == null || key.length < 7) continue;
      final monthKey = key.substring(0, 7);
      result[monthKey] =
          (result[monthKey] ?? 0) + toDoubleValue(row['revenue']);
    }
    return result;
  }

  static String dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String monthKey(int year, int month) {
    return '$year-${month.toString().padLeft(2, '0')}';
  }

  static double toDoubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _RevenueDashboardData {
  final Map<String, dynamic> revenue;

  const _RevenueDashboardData({required this.revenue});
}
