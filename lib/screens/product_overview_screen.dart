import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class ProductOverviewScreen extends StatefulWidget {
  const ProductOverviewScreen({super.key});

  @override
  State<ProductOverviewScreen> createState() => _ProductOverviewScreenState();
}

class _ProductOverviewScreenState extends State<ProductOverviewScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, String>> _products = [
    {
      'name': 'TÃ¡o Ä‘á»',
      'image': 'assets/images/tao.png',
      'date': '26/8/2025',
    },
    {
      'name': 'NÆ°á»›c Coca',
      'image': 'assets/images/nuoccoca.png',
      'date': '27/7/2025',
    },
    {
      'name': 'Dáº§u gá»™i Dove',
      'image': 'assets/images/default_product.png',
      'date': '26/6/2025',
    },
    {
      'name': 'MÃ¬ Háº£o Háº£o',
      'image': 'assets/images/default_product.png',
      'date': '25/6/2025',
    },
  ];

  @override
  void initState() {
    _tabController = TabController(length: 2, vsync: this);
    super.initState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sáº£n pháº©m má»›i',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.black54,
          tabs: const [
            Tab(text: 'Tá»•ng quan'),
            Tab(text: 'Danh sÃ¡ch'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildOverviewTab(), _buildListTab()],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildInfoCard('Tá»•ng sáº£n pháº©m má»›i', '20'),
              const SizedBox(width: 12),
              _buildInfoCard('Äang hoáº¡t Ä‘á»™ng', '18'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoCard('Doanh thu', '2.000.000 Ä‘'),
              const SizedBox(width: 12),
              _buildInfoCard('Tá»· lá»‡ thÃ nh cÃ´ng', '80%'),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Xu hÆ°á»›ng thÃªm sáº£n pháº©m',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(
                    color: Colors.pink.shade200,
                    value: 45,
                    title: '45%',
                    radius: 50,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  PieChartSectionData(
                    color: Colors.purple.shade300,
                    value: 45,
                    title: '45%',
                    radius: 50,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  PieChartSectionData(
                    color: Colors.blue.shade200,
                    value: 10,
                    title: '10%',
                    radius: 50,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('â€¢ Hoa quáº£', style: TextStyle(color: Colors.pink)),
          const Text(
            'â€¢ Äá»“ gia dá»¥ng',
            style: TextStyle(color: Colors.purple),
          ),
          const Text(
            'â€¢ NÆ°á»›c uá»‘ng',
            style: TextStyle(color: Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildListTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'TÃ¬m kiáº¿m sáº£n pháº©m',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _products.length,
              itemBuilder: (context, index) {
                final p = _products[index];
                if (_searchController.text.isNotEmpty &&
                    !p['name']!.toLowerCase().contains(
                      _searchController.text.toLowerCase(),
                    )) {
                  return const SizedBox.shrink();
                }
                return Card(
                  elevation: 0.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        p['image']!,
                        width: 45,
                        height: 45,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Image.asset(
                          'assets/images/default_product.png',
                          width: 45,
                          height: 45,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    title: Text(
                      p['name']!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('ThÃªm ${p['date']!}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
