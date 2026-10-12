// lib/screens/inventory_management_screen.dart (ĐÃ CẬP NHẬT: Kết nối nút Sắp hết hàng)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sieuthimini/screens/import_inventory_screen.dart';

import '../models/inventory_item.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../utils/constants.dart';
import '../utils/product_asset_resolver.dart';
import 'edit_inventory_item_screen.dart';
import 'inventory_check_screen.dart';
import 'inventory_history_screen.dart'; // Màn hình lịch sử xuất nhập kho
import 'low_stock_screen.dart'; // 💡 IMPORT MÀN HÌNH MỚI

class InventoryManagementScreen extends StatefulWidget {
  const InventoryManagementScreen({super.key});

  @override
  State<InventoryManagementScreen> createState() =>
      _InventoryManagementScreenState();
}

class _InventoryManagementScreenState extends State<InventoryManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  static const String _allCategoryLabel = 'Tất cả';
  String _selectedCategory = _allCategoryLabel;
  Map<int, String> _categoryNamesById = {};

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categoryNamesById = {
          for (final category in categories)
            if (_categoryIdOf(category) != null)
              _categoryIdOf(category)!:
                  category['category_name']?.toString().trim() ?? '',
        }..removeWhere((_, name) => name.isEmpty);
      });
    } catch (_) {
      if (mounted) setState(() => _categoryNamesById = {});
    }
  }

  int? _categoryIdOf(Map<String, dynamic> category) {
    final id = category['category_id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- HÀM TÍNH TOÁN VÀ ĐIỀU HƯỚNG ---

  Map<String, dynamic> _calculateInventoryStats(Box<InventoryItem> box) {
    double totalValue = 0;
    int lowStockCount = 0;

    for (var item in box.values) {
      totalValue += item.stockQuantity * item.price;

      if (item.stockQuantity <= AppConstants.minStockThreshold) {
        lowStockCount++;
      }
    }
    return {'totalValue': totalValue, 'lowStockCount': lowStockCount};
  }

  // 💡 HÀM ĐIỀU HƯỚNG ĐẾN DANH SÁCH SẮP HẾT HÀNG
  void _onLowStockPressed() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LowStockScreen()));
  }

  // (Giữ nguyên các hàm điều hướng khác: _onImportInventoryPressed, _onExportInventoryPressed, _onCheckInventoryPressed)

  void _onImportInventoryPressed() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ImportInventoryScreen()));
    if (!mounted) return;
    await _loadCategories();
  }

  void _onHistoryInventoryPressed() async {
    // Chuyển sang màn hình Lịch sử xuất/nhập kho
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const InventoryHistoryScreen()));
  }

  void _onCheckInventoryPressed() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const InventoryCheckScreen()));
  }

  // --- WIDGET HỖ TRỢ (Giữ nguyên) ---

  Widget _buildQuickActionButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    // ... (Giữ nguyên code của _buildQuickActionButton)
    return Expanded(
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.blue.shade700, size: 30),
            ),
          ),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildInventoryTile(BuildContext context, InventoryItem item) {
    String status;
    Color statusColor;

    if (item.stockQuantity == 0) {
      status = 'Hết hàng';
      statusColor = Colors.red;
    } else if (item.stockQuantity <= AppConstants.minStockThreshold) {
      status = 'Sắp hết';
      statusColor = Colors.orange;
    } else {
      status = 'Còn hàng';
      statusColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddInventoryItemScreen(item: item),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _buildInventoryImage(item),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mã vạch / Mã nội bộ: ${item.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _inventoryInfoChip(
                    Icons.inventory_outlined,
                    'Tồn kho',
                    '${item.stockQuantity} ${item.unit}',
                    statusColor,
                  ),
                  _inventoryInfoChip(
                    Icons.straighten,
                    'Đơn vị',
                    item.unit,
                    Colors.blueGrey,
                  ),
                  _inventoryInfoChip(
                    Icons.call_received,
                    'Giá nhập',
                    '${item.importPrice?.toStringAsFixed(0) ?? '-'} đ',
                    Colors.teal,
                  ),
                  _inventoryInfoChip(
                    Icons.sell_outlined,
                    'Giá bán',
                    '${item.price.toStringAsFixed(0)} đ',
                    Colors.deepOrange,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _onImportInventoryPressed,
                  icon: const Icon(Icons.add_box_outlined, size: 18),
                  label: const Text('Nhập thêm'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryImage(InventoryItem item) {
    final storedRaw =
        (DBService.productImages().get(item.id) ?? item.imageUrl ?? '')
            .toString();
    final stored = ApiService.resolveBackendUrl(storedRaw);

    if (storedRaw.trim().startsWith('assets/')) {
      return _inventoryAssetImage(item, storedRaw.trim());
    }

    if (stored.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          stored,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _inventoryAssetImage(item),
        ),
      );
    }

    if (stored.isNotEmpty) {
      try {
        final file = File(stored);
        if (file.existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(file, width: 48, height: 48, fit: BoxFit.cover),
          );
        }
      } catch (_) {}
    }

    return _inventoryAssetImage(item);
  }

  Widget _inventoryAssetImage(InventoryItem item, [String? preferredAsset]) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        preferredAsset ?? ProductAssetResolver.forInventoryItem(item),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          ProductAssetResolver.defaultProductAsset,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _inventoryInfoChip(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _inventoryCategory(InventoryItem item, List<Product> products) {
    final itemCategoryId = item.categoryId;
    if (itemCategoryId != null) {
      final name = _categoryNamesById[itemCategoryId]?.trim();
      if (name != null && name.isNotEmpty) return name;
      return 'Danh mục $itemCategoryId';
    }

    Product? mappedProduct;
    for (final p in products) {
      if (p.barcode == item.id || p.id == item.id) {
        mappedProduct = p;
        break;
      }
    }
    if (mappedProduct == null) return 'Chưa lên kệ';
    final name = mappedProduct.categoryName?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (mappedProduct.categoryId != null) {
      return 'Danh mục ${mappedProduct.categoryId}';
    }
    return 'Chưa phân loại';
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: Colors.blue.shade800,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quản lý Kho',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 1,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thanh tìm kiếm (Giữ nguyên)
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
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Tìm tên hoặc mã vạch / mã nội bộ',
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

          // --- PHẦN THỐNG KÊ ---
          ValueListenableBuilder<Box<InventoryItem>>(
            valueListenable: DBService.inventoryProducts().listenable(),
            builder: (context, box, _) {
              final stats = _calculateInventoryStats(box);

              final String totalValueStr = (stats['totalValue'] as double)
                  .toStringAsFixed(0)
                  .replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                    (Match m) => '${m[1]}.',
                  );

              final int lowStockCount = stats['lowStockCount'] as int;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Card(
                        elevation: 1,
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Giá trị kho',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '$totalValueStr đ',
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.inventory_2,
                                    color: Colors.green,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        // 💡 WRAP BẰNG GESTUREDETECTOR HOẶC INKWELL
                        onTap: _onLowStockPressed, // GỌI HÀM MỚI
                        child: Card(
                          elevation: 1,
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sắp hết hàng',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          '$lowStockCount SP',
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      color: Colors.red,
                                      size: 22,
                                    ),
                                  ],
                                ),
                              ],
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

          // --- KẾT THÚC PHẦN THỐNG KÊ ---
          const Padding(
            padding: EdgeInsets.only(left: 16.0, top: 12.0),
            child: Text(
              'Tác vụ nhanh',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),

          // --- Dãy 3 NÚT TÁC VỤ NHANH (Giữ nguyên) ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildQuickActionButton(
                  title: 'Nhập kho',
                  icon: Icons.add_circle_outline,
                  onTap: _onImportInventoryPressed,
                ),
                _buildQuickActionButton(
                  title: 'Lịch sử',
                  icon: Icons.history,
                  onTap: _onHistoryInventoryPressed,
                ),
                _buildQuickActionButton(
                  title: 'Kiểm kê',
                  icon: Icons.compare_arrows,
                  onTap: _onCheckInventoryPressed,
                ),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),

          const Padding(
            padding: EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
            child: Text(
              'Danh sách tồn kho',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ValueListenableBuilder<Box<InventoryItem>>(
            valueListenable: DBService.inventoryProducts().listenable(),
            builder: (context, box, _) {
              final products = DBService.products().values
                  .toList()
                  .cast<Product>();
              final items = box.values.toList();
              final categories =
                  <String>{
                    _allCategoryLabel,
                    ...items.whereType<InventoryItem>().map(
                      (it) => _inventoryCategory(it, products),
                    ),
                  }.toList()..sort((a, b) {
                    if (a == _allCategoryLabel) return -1;
                    if (b == _allCategoryLabel) return 1;
                    return a.compareTo(b);
                  });

              if (_selectedCategory != _allCategoryLabel &&
                  !categories.contains(_selectedCategory)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _selectedCategory = _allCategoryLabel);
                  }
                });
              }

              return Padding(
                padding: const EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  bottom: 8.0,
                ),
                child: SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: categories
                        .map(
                          (category) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: _selectedCategory == category,
                              onSelected: (_) =>
                                  setState(() => _selectedCategory = category),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              );
            },
          ),

          // PHẦN CUỘN: Danh sách sản phẩm (Giữ nguyên)
          Expanded(
            child: ValueListenableBuilder<Box<InventoryItem>>(
              valueListenable: DBService.inventoryProducts().listenable(),
              builder: (context, box, _) {
                final products = DBService.products().values
                    .toList()
                    .cast<Product>();
                final query = _searchController.text.trim().toLowerCase();
                final List<InventoryItem> items = box.values.where((it) {
                  if (query.isEmpty) return true;
                  return it.id.toLowerCase().contains(query) ||
                      it.name.toLowerCase().contains(query);
                }).toList();

                List<InventoryItem> displayItems = items;
                if (_selectedCategory != _allCategoryLabel) {
                  displayItems = items
                      .where(
                        (it) =>
                            _inventoryCategory(it, products) ==
                            _selectedCategory,
                      )
                      .toList();
                }

                // Sort: low stock first, then name
                displayItems.sort((a, b) {
                  final cmp = a.stockQuantity.compareTo(b.stockQuantity);
                  if (cmp != 0) return cmp;
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });

                if (displayItems.isEmpty) {
                  return const Center(
                    child: Text(
                      'Kho hàng đang trống hoặc không có kết quả phù hợp.',
                    ),
                  );
                }

                final Map<String, List<InventoryItem>> grouped = {};
                for (final item in displayItems) {
                  final category = _inventoryCategory(item, products);
                  grouped
                      .putIfAbsent(category, () => <InventoryItem>[])
                      .add(item);
                }

                return ListView(
                  padding: const EdgeInsets.only(
                    left: 16.0,
                    right: 16.0,
                    bottom: 16.0,
                  ),
                  children: [
                    ...grouped.entries.expand((entry) {
                      return <Widget>[
                        _buildSectionHeader(entry.key, entry.value.length),
                        ...entry.value.map(
                          (item) => _buildInventoryTile(context, item),
                        ),
                      ];
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
