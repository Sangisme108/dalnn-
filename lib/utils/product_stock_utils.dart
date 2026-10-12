import 'package:flutter/material.dart';

import '../models/product.dart';

enum ProductStockLevel { inStock, lowStock, outOfStock }

class ProductStockUtils {
  static const Color primaryGreen = Color(0xFF1B7F4D);

  static ProductStockLevel level(Product product) {
    if (product.stockQuantity <= 0) return ProductStockLevel.outOfStock;
    if (product.stockQuantity <= product.minStock) {
      return ProductStockLevel.lowStock;
    }
    return ProductStockLevel.inStock;
  }

  static String label(Product product) {
    switch (level(product)) {
      case ProductStockLevel.outOfStock:
        return 'Hết hàng';
      case ProductStockLevel.lowStock:
        return 'Sắp hết';
      case ProductStockLevel.inStock:
        return 'Còn hàng';
    }
  }

  static Color color(Product product) {
    switch (level(product)) {
      case ProductStockLevel.outOfStock:
        return Colors.red.shade600;
      case ProductStockLevel.lowStock:
        return Colors.orange.shade700;
      case ProductStockLevel.inStock:
        return primaryGreen;
    }
  }

  static bool canPurchase(Product product) => product.stockQuantity > 0;

  static bool isSellable(Product product) {
    final status = (product.status ?? 'active').toLowerCase();
    return status == 'active' && canPurchase(product);
  }
}
