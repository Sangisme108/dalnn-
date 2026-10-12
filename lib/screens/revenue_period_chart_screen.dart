import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/db_service.dart';

class RevenuePeriodChartScreen extends StatefulWidget {
  final RevenuePeriod period;
  const RevenuePeriodChartScreen({super.key, required this.period});

  @override
  State<RevenuePeriodChartScreen> createState() =>
      _RevenuePeriodChartScreenState();
}

enum RevenuePeriod { day, month, year }

class _RevenuePeriodChartScreenState extends State<RevenuePeriodChartScreen> {
  late Future<_RevenuePeriodChartData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RevenuePeriodChartData> _load() async {
    final rawUserId = DBService.settings().get('current_user_id');
    final adminUserId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '');
    if (adminUserId == null) {
      throw ApiException('Thiếu thông tin admin');
    }

    final revenue = await ApiService.fetchRevenueReport(adminUserId);
    return _RevenuePeriodChartData.fromApi(revenue, widget.period);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForPeriod(widget.period)),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<_RevenuePeriodChartData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data = snapshot.data!;

          if (data.points.isEmpty) {
            return const Center(
              child: Text('Chưa có dữ liệu doanh thu theo giai đoạn'),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.bar_chart, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tổng doanh thu: ${data.totalRevenueFormatted}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: BarChart(
                    BarChartData(
                      barGroups: data.points.asMap().entries.map((e) {
                        final index = e.key;
                        final p = e.value;
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: p.revenue,
                              width: 12,
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.blue.shade600,
                            ),
                          ],
                        );
                      }).toList(),
                      gridData: const FlGridData(
                        show: true,
                        drawVerticalLine: false,
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
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
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= data.points.length) {
                                return const SizedBox.shrink();
                              }
                              final label = data.points[i].label;
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                space: 6,
                                child: Text(
                                  label,
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
                            final p = data.points[groupIndex];
                            return BarTooltipItem(
                              '${p.label}\n',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      'Doanh thu: ${p.revenue.toStringAsFixed(0)} đ',
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
        },
      ),
    );
  }

  String _titleForPeriod(RevenuePeriod p) {
    switch (p) {
      case RevenuePeriod.day:
        return 'Biểu đồ doanh thu theo ngày';
      case RevenuePeriod.month:
        return 'Biểu đồ doanh thu theo tháng';
      case RevenuePeriod.year:
        return 'Biểu đồ doanh thu theo năm';
    }
  }
}

class _RevenuePeriodChartPoint {
  final String label;
  final double revenue;
  _RevenuePeriodChartPoint({required this.label, required this.revenue});
}

class _RevenuePeriodChartData {
  final List<_RevenuePeriodChartPoint> points;
  final double totalRevenue;

  _RevenuePeriodChartData({required this.points, required this.totalRevenue});

  String get totalRevenueFormatted =>
      '${totalRevenue.round().toString().replaceAllMapped(RegExp(r'(\\d{1,3})(?=(\\d{3})+(?!\\d))'), (m) => '${m[1]}.')} đ';

  factory _RevenuePeriodChartData.fromApi(
    Map<String, dynamic> api,
    RevenuePeriod period,
  ) {
    final list = <dynamic>[];
    if (period == RevenuePeriod.day) {
      list.addAll(api['revenue_by_time'] ?? const []);
    } else if (period == RevenuePeriod.month) {
      list.addAll(api['revenue_by_month'] ?? const []);
    } else {
      list.addAll(api['revenue_by_year'] ?? const []);
    }

    final points = list.whereType<Map>().map((row) {
      final periodStr = row['period']?.toString() ?? '';
      final revenue = row['revenue'] ?? 0;
      final label = _shortLabelForPeriod(periodStr, period);
      return _RevenuePeriodChartPoint(
        label: label,
        revenue: revenue is num
            ? revenue.toDouble()
            : double.tryParse(revenue.toString()) ?? 0,
      );
    }).toList();

    final total = points.fold(0.0, (s, e) => s + e.revenue);
    return _RevenuePeriodChartData(points: points, totalRevenue: total);
  }

  static String _shortLabelForPeriod(String periodStr, RevenuePeriod p) {
    // day: YYYY-MM-DD
    // month: YYYY-MM-01
    // year: YYYY-01-01
    if (p == RevenuePeriod.day) {
      if (periodStr.length >= 10) return periodStr.substring(8, 10);
      return periodStr;
    }
    if (p == RevenuePeriod.month) {
      if (periodStr.length >= 7) return periodStr.substring(5, 7);
      return periodStr;
    }
    // year
    if (periodStr.length >= 4) return periodStr.substring(0, 4);
    return periodStr;
  }
}
