import '../utils/type_converters.dart';

/// Đánh giá sản phẩm — map từ API `/api/reviews/products/:id`.
class ProductReview {
  final int? id;
  final String productId;
  final int? customerId;
  final String customerName;
  final int rating;
  final String comment;
  final DateTime? createdAt;

  const ProductReview({
    this.id,
    required this.productId,
    this.customerId,
    required this.customerName,
    required this.rating,
    required this.comment,
    this.createdAt,
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    return ProductReview(
      id: TypeConverters.toNullableInt(json['review_id'] ?? json['id']),
      productId: (json['product_id'] ?? json['productId'] ?? '').toString(),
      customerId: TypeConverters.toNullableInt(
        json['user_id'] ?? json['customer_id'] ?? json['customerId'],
      ),
      customerName:
          (json['full_name'] ??
                  json['customer_name'] ??
                  json['customerName'] ??
                  'Khách hàng')
              .toString(),
      rating: TypeConverters.toInt(json['rating'], defaultValue: 5).clamp(1, 5),
      comment: (json['comment'] ?? '').toString(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'review_id': id,
    'product_id': int.tryParse(productId) ?? productId,
    if (customerId != null) 'customer_id': customerId,
    'customer_name': customerName,
    'rating': rating,
    'comment': comment,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };

  static double averageRating(List<ProductReview> reviews) {
    if (reviews.isEmpty) return 0;
    final sum = reviews.fold<int>(0, (acc, r) => acc + r.rating);
    return sum / reviews.length;
  }
}
