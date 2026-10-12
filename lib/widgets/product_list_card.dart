import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/product_stock_utils.dart';

/// Card sản phẩm khách hàng: vùng chính mở chi tiết, nút giỏ tách riêng.
class ProductListCard extends StatelessWidget {
  final Product product;
  final String categoryLabel;
  final String priceText;
  final Widget image;
  final VoidCallback onOpenDetail;
  final VoidCallback? onAddToCart;

  const ProductListCard({
    super.key,
    required this.product,
    required this.categoryLabel,
    required this.priceText,
    required this.image,
    required this.onOpenDetail,
    this.onAddToCart,
  });

  bool get _outOfStock => !ProductStockUtils.canPurchase(product);

  @override
  Widget build(BuildContext context) {
    final stockColor = ProductStockUtils.color(product);
    final stockLabel = ProductStockUtils.label(product);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onOpenDetail,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ColoredBox(
                                color: const Color(0xFFF1F3F5),
                                child: image,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                stockLabel,
                                style: TextStyle(
                                  color: stockColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$categoryLabel • ${product.unit}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          'Tồn ${product.stockQuantity}',
                          style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpenDetail,
                    child: Text(
                      priceText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: ProductStockUtils.primaryGreen,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 38,
                  height: 38,
                  child: IconButton.filled(
                    padding: EdgeInsets.zero,
                    tooltip: _outOfStock ? 'Hết hàng' : 'Thêm vào giỏ',
                    style: IconButton.styleFrom(
                      backgroundColor: _outOfStock
                          ? Colors.grey.shade300
                          : ProductStockUtils.primaryGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _outOfStock ? null : onAddToCart,
                    icon: Icon(
                      _outOfStock ? Icons.remove_shopping_cart : Icons.add_shopping_cart,
                      size: 19,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
