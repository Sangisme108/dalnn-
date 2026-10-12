// lib/models/order_line.dart
import 'package:hive/hive.dart';
import '../utils/type_converters.dart';

part 'order_line.g.dart';

@HiveType(typeId: 3) // Chọn typeId chưa dùng (3)
class OrderLine extends HiveObject {
  @HiveField(0)
  String productId;

  @HiveField(1)
  String productName; // Giúp hiển thị nhanh

  @HiveField(2)
  int quantity;

  @HiveField(3)
  double pricePerUnit;

  OrderLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.pricePerUnit,
  });

  factory OrderLine.fromJson(Map<String, dynamic> json) {
    return OrderLine(
      productId: (json['product_id'] ?? json['productId']).toString(),
      productName: (json['product_name'] ?? json['productName'] ?? '')
          .toString(),
      quantity: TypeConverters.toInt(json['quantity']),
      pricePerUnit: TypeConverters.toDouble(
        json['unitPrice'] ?? json['pricePerUnit'] ?? json['price'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': int.tryParse(productId),
      'product_name': productName,
      'quantity': quantity,
      'price': pricePerUnit,
    };
  }
}
