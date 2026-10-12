// lib/screens/new_products_screen.dart

import 'package:flutter/material.dart';
import '../models/product.dart'; // Import model Product của bạn

class NewProductsScreen extends StatelessWidget {
  // Nhận danh sách SẢN PHẨM MỚI đã được lọc sẵn
  final List<Product> newProducts;

  const NewProductsScreen({super.key, required this.newProducts});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sản phẩm mới đã thêm')),
      body: newProducts.isEmpty
          ? Center(child: Text('Không có sản phẩm mới nào (trong 24h qua).'))
          : ListView.builder(
              itemCount: newProducts.length,
              itemBuilder: (ctx, index) {
                final product = newProducts[index];

                // Bạn có thể dùng lại widget hiển thị sản phẩm
                // từ màn hình "Quản lý Sản phẩm"
                return ListTile(
                  leading: Icon(Icons.shopping_bag_outlined),
                  title: Text(product.name),
                  subtitle: Text(
                    'Mã vạch / mã nội bộ: ${product.barcode ?? product.id} | Đơn vị: ${product.unit}',
                  ),
                  trailing: Text('Tồn: ${product.stockQuantity}'),
                );
              },
            ),
    );
  }
}
