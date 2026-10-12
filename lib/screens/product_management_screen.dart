import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/product.dart';
import '../services/db_service.dart';
import 'edit_product_screen.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';
import '../utils/product_asset_resolver.dart';
import '../utils/product_stock_utils.dart';
import '../widgets/product_image_widget.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'Tất cả';
  String _selectedCategory = 'Tất cả';

  // --- HÀM HỖ TRỢ ---

  Map<String, dynamic> _getStockStatus(Product product) {
    if (!(product.isActive)) {
      return {'status': 'Ngừng bán', 'color': Colors.grey.shade700};
    }
    return {
      'status': ProductStockUtils.label(product),
      'color': ProductStockUtils.color(product),
    };
  }

  String _assetFallback(Product p) => ProductAssetResolver.forProduct(p);

  String _getCategoryName(Product product) {
    final categoryName = product.categoryName?.trim();
    if (categoryName != null && categoryName.isNotEmpty) return categoryName;
    final byId = product.categoryId;
    if (byId == null) return 'Chưa phân loại';
    return 'Danh mục $byId';
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

  // Xóa sản phẩm qua API rồi cập nhật cache Hive
  Future<void> _deleteProduct(BuildContext context, Product product) async {
    final bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Xác nhận xóa'),
            content: Text(
              'Bạn có chắc chắn muốn xóa sản phẩm "${product.name}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Hủy'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Xóa', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      try {
        await DBService.deleteProductRemote(product);
        // Sử dụng mounted check trước khi gọi ScaffoldMessenger
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xóa sản phẩm ${product.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi khi xóa: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _navigateToView(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: product,
          assetFallback: _assetFallback,
          readOnly: true,
        ),
      ),
    );
  }

  Future<void> _navigateToEdit(Product product) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditProductScreen(product: product)),
    );
    if (updated == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _deactivateProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ngừng bán sản phẩm'),
        content: Text('Ngừng bán "${product.name}" trên kệ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ngừng bán'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      product.status = 'inactive';
      await DBService.updateProductRemote(product);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Đã ngừng bán ${product.name}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Widget hiển thị một sản phẩm trong danh sách
  Widget _buildProductTile(BuildContext context, Product product) {
    final statusData = _getStockStatus(product);
    final String status = statusData['status'];
    final Color statusColor = statusData['color'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        // 1. Ảnh
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 50,
            height: 50,
            color: Colors.blue.shade50,
            child: ProductImageWidget(
              product: product,
              assetFallback: _assetFallback,
            ),
          ),
        ),

        // 2. Thông tin chính
        title: Text(
          product.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mã vạch / mã nội bộ: ${product.barcode ?? product.id}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Text(
              '${product.price.round().toString()} ₫ / ${product.unit}',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),

        // 3. Tồn kho và Trạng thái
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Tồn: ${product.stockQuantity}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: statusColor, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            // Nút Thao tác (Popup Menu)
            PopupMenuButton<String>(
              onSelected: (String result) {
                switch (result) {
                  case 'view':
                    _navigateToView(product);
                    break;
                  case 'edit':
                    _navigateToEdit(product);
                    break;
                  case 'deactivate':
                    _deactivateProduct(product);
                    break;
                  case 'delete':
                    _deleteProduct(context, product);
                    break;
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'view',
                  child: ListTile(
                    leading: Icon(Icons.visibility_outlined, size: 20),
                    title: Text('Xem chi tiết'),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit, size: 20),
                    title: Text('Chỉnh sửa'),
                  ),
                ),
                if (product.isActive)
                  const PopupMenuItem<String>(
                    value: 'deactivate',
                    child: ListTile(
                      leading: Icon(Icons.block, size: 20),
                      title: Text('Ngừng bán'),
                    ),
                  ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red, size: 20),
                    title: Text(
                      'Xóa sản phẩm',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _navigateToView(product),
      ),
    );
  }

  // --- WIDGET CHÍNH ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quản lý Sản phẩm',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 1. Thanh tìm kiếm
          Padding(
            padding: const EdgeInsets.all(16.0).copyWith(bottom: 8),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: const InputDecoration(
                hintText: 'Tìm kiếm theo tên hoặc mã...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Color(0xFFF3F4F6),
                isDense: true,
              ),
            ),
          ),

          // 2. Bộ lọc
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                _buildFilterChip('Tất cả'),
                _buildFilterChip('Còn hàng'),
                _buildFilterChip('Sắp hết'),
                _buildFilterChip('Hết hàng'),
              ],
            ),
          ),
          ValueListenableBuilder<Box<Product>>(
            valueListenable: DBService.products().listenable(),
            builder: (context, box, _) {
              final allProducts = box.values.toList().cast<Product>();
              final categories = <String>{
                'Tất cả',
                ...allProducts.map(_getCategoryName),
              }.toList();
              categories.sort((a, b) {
                if (a == 'Tất cả') return -1;
                if (b == 'Tất cả') return 1;
                return a.compareTo(b);
              });

              if (_selectedCategory != 'Tất cả' &&
                  !categories.contains(_selectedCategory)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _selectedCategory = 'Tất cả');
                  }
                });
              }

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 2.0,
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
          const SizedBox(height: 4),

          // 3. Danh sách sản phẩm thực tế (Kết nối Hive)
          Expanded(
            child: ValueListenableBuilder<Box<Product>>(
              valueListenable: DBService.products().listenable(),
              builder: (context, box, _) {
                // Lấy tất cả sản phẩm
                List<Product> allProducts = DBService.getAllProducts();

                // Lọc theo tìm kiếm
                List<Product> filteredProducts = DBService.searchProducts(
                  _searchQuery,
                  allProducts,
                );

                if (_selectedCategory != 'Tất cả') {
                  filteredProducts = filteredProducts
                      .where((p) => _getCategoryName(p) == _selectedCategory)
                      .toList();
                }

                // 💡 LOGIC LỌC THEO TRẠNG THÁI MỚI
                if (_selectedFilter != 'Tất cả') {
                  filteredProducts = filteredProducts.where((product) {
                    final label = ProductStockUtils.label(product);
                    if (_selectedFilter == 'Hết hàng') {
                      return label == 'Hết hàng';
                    } else if (_selectedFilter == 'Sắp hết') {
                      return label == 'Sắp hết';
                    } else if (_selectedFilter == 'Còn hàng') {
                      return label == 'Còn hàng';
                    }
                    return true;
                  }).toList();
                }

                if (filteredProducts.isEmpty) {
                  return Center(
                    child: Text(
                      'Không tìm thấy sản phẩm nào${_searchQuery.isNotEmpty ? ' khớp với tìm kiếm' : ''}.',
                    ),
                  );
                }

                // Sắp xếp: danh mục -> tên
                filteredProducts.sort((a, b) {
                  final cateCmp = _getCategoryName(
                    a,
                  ).compareTo(_getCategoryName(b));
                  if (cateCmp != 0) return cateCmp;
                  return a.name.compareTo(b.name);
                });

                final Map<String, List<Product>> grouped = {};
                for (final product in filteredProducts) {
                  final category = _getCategoryName(product);
                  grouped.putIfAbsent(category, () => <Product>[]).add(product);
                }

                return ListView(
                  padding: const EdgeInsets.all(16.0).copyWith(top: 8),
                  children: [
                    ...grouped.entries.expand((entry) {
                      return <Widget>[
                        _buildSectionHeader(entry.key, entry.value.length),
                        ...entry.value.map(
                          (p) => _buildProductTile(context, p),
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

      // Nút Thêm sản phẩm
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AddProductScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('Thêm Sản phẩm'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
    );
  }

  // Widget cho các chip lọc
  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) {
            setState(() {
              _selectedFilter = label;
            });
          }
        },
        selectedColor: Colors.blue.shade100,
        backgroundColor: Colors.grey.shade100,
        labelStyle: TextStyle(
          color: isSelected ? Colors.blue.shade900 : Colors.black54,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isSelected
              ? BorderSide(color: Colors.blue.shade400)
              : BorderSide.none,
        ),
      ),
    );
  }
}
