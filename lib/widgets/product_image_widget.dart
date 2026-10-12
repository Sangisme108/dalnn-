import 'dart:io';

import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../utils/product_asset_resolver.dart';

/// Hiển thị ảnh sản phẩm: URL mạng, file local, hoặc asset fallback.
class ProductImageWidget extends StatelessWidget {
  final Product product;
  final String Function(Product) assetFallback;
  final BoxFit fit;
  final double? height;

  const ProductImageWidget({
    super.key,
    required this.product,
    required this.assetFallback,
    this.fit = BoxFit.cover,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final storedRaw =
        (DBService.productImages().get(product.id) ?? product.imageUrl ?? '')
            .toString();
    final stored = ApiService.resolveBackendUrl(storedRaw);

    Widget image;
    if (storedRaw.trim().startsWith('assets/')) {
      image = _assetImage(storedRaw.trim());
    } else if (stored.isNotEmpty && stored.startsWith('http')) {
      image = Image.network(
        stored,
        fit: fit,
        width: double.infinity,
        height: height,
        errorBuilder: (_, __, ___) => _assetImage(),
      );
    } else if (stored.isNotEmpty) {
      try {
        final file = File(stored);
        if (file.existsSync()) {
          image = Image.file(
            file,
            fit: fit,
            width: double.infinity,
            height: height,
            errorBuilder: (_, __, ___) => _assetImage(),
          );
        } else {
          image = _assetImage();
        }
      } catch (_) {
        image = _assetImage();
      }
    } else {
      image = _assetImage();
    }

    return image;
  }

  Widget _assetImage([String? preferredAsset]) {
    final resolvedAsset = ProductAssetResolver.forProduct(product);
    final asset =
        preferredAsset ??
        (resolvedAsset == ProductAssetResolver.defaultProductAsset
            ? assetFallback(product)
            : resolvedAsset);
    return Image.asset(
      asset,
      fit: fit,
      width: double.infinity,
      height: height,
      errorBuilder: (_, __, ___) => Image.asset(
        ProductAssetResolver.defaultProductAsset,
        fit: fit,
        width: double.infinity,
        height: height,
      ),
    );
  }
}
