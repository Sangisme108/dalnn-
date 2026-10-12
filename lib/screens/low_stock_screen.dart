// lib/screens/low_stock_screen.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_item.dart';
import '../services/db_service.dart';
import '../utils/constants.dart';

class LowStockScreen extends StatelessWidget {
  const LowStockScreen({super.key});

  // Widget hiển thị từng sản phẩm
  Widget _buildProductTile(BuildContext context, InventoryItem product) {
    // Determine status and color based on stock
    String status;
    Color statusColor;
    IconData leadingIcon;
    Color leadingBg;

    if (product.stockQuantity == 0) {
      status = 'Hết hàng';
      statusColor = Colors.red;
      leadingIcon = Icons.block;
      leadingBg = Colors.red.shade50;
    } else if (product.stockQuantity <= AppConstants.minStockThreshold) {
      status = 'Sắp hết';
      statusColor = Colors.orange;
      leadingIcon = Icons.warning_amber_rounded;
      leadingBg = Colors.orange.shade50;
    } else {
      status = 'Còn hàng';
      statusColor = Colors.green;
      leadingIcon = Icons.inventory_2_outlined;
      leadingBg = Colors.green.shade50;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.3), width: 1.5),
      ),
      child: ListTile(
        // onTap: () async {
        //   // Khi ấn vào, điều hướng đến màn hình Thêm/Sửa để nhập thêm hàng
        //   await Navigator.of(context).push(
        //     MaterialPageRoute(
        //       builder: (_) => AddInventoryItemScreen(item: product),
        //     ),
        //   );
        // },
        leading: Container(
          width: 50,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: leadingBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(leadingIcon, color: statusColor, size: 28),
        ),
        title: Text(
          product.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: status == 'Hết hàng' ? Colors.red : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mã vạch / mã nội bộ: ${product.id}'),
            Text(
              'Giá: ${product.price.toStringAsFixed(0)} đ / ${product.unit}',
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Tồn: ${product.stockQuantity} ${product.unit}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(status, style: TextStyle(fontSize: 12, color: statusColor)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sản phẩm Sắp hết hàng',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red.shade400,
        foregroundColor: Colors.white,
      ),
      body: ValueListenableBuilder<Box<InventoryItem>>(
        valueListenable: DBService.inventoryProducts().listenable(),
        builder: (context, box, _) {
          // Lọc ra các sản phẩm sắp hết hàng trong kho (InventoryItem)
          final List<InventoryItem> lowStockProducts = box.values
              .where((p) => p.stockQuantity <= AppConstants.minStockThreshold)
              .toList();

          // Sort so out-of-stock (0) appear first, then ascending by stock
          lowStockProducts.sort(
            (a, b) => a.stockQuantity.compareTo(b.stockQuantity),
          );

          if (lowStockProducts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.thumb_up_alt_outlined,
                      color: Colors.green,
                      size: 50,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Tuyệt vời! Hiện tại không có sản phẩm nào sắp hết hàng.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.green),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: lowStockProducts.length,
            itemBuilder: (context, index) {
              return _buildProductTile(context, lowStockProducts[index]);
            },
          );
        },
      ),
    );
  }
}
