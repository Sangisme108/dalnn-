// lib/models/order.dart
import 'package:hive/hive.dart';
import 'order_line.dart'; // Import OrderLine
import '../utils/type_converters.dart';

part 'order.g.dart'; // File tự động tạo bởi build_runner

@HiveType(typeId: 2) // Chọn typeId chưa dùng (2)
class Order extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime orderDate;

  @HiveField(2)
  double totalAmount;

  @HiveField(3)
  String customerName;

  @HiveField(4)
  String status; // Ví dụ: 'Hoàn thành', 'Đang xử lý', 'Đã hủy'

  @HiveField(5)
  List<OrderLine> items; // Danh sách sản phẩm trong đơn hàng

  @HiveField(6)
  int? customerId;

  @HiveField(7)
  String? shippingAddress;

  @HiveField(8)
  String? paymentMethod;

  @HiveField(9)
  String? paymentStatus;

  @HiveField(10)
  String? note;

  @HiveField(11)
  int? voucherId; // Mã voucher được áp dụng

  @HiveField(12)
  double discountAmount; // Số tiền giảm

  @HiveField(13)
  String orderType;

  @HiveField(14)
  String? deliveryMethod;

  @HiveField(15)
  String? transactionId;

  @HiveField(16)
  DateTime? paidAt;

  @HiveField(17)
  String? qrContent;

  @HiveField(18)
  String? transferContent;

  @HiveField(19)
  int pointsUsed;

  @HiveField(20)
  int pointsEarned;

  @HiveField(21)
  double pointsDiscount;

  @HiveField(22)
  String? customerPhone;

  Order({
    required this.id,
    required this.orderDate,
    required this.totalAmount,
    required this.customerName,
    required this.status,
    required this.items,
    this.customerId,
    this.shippingAddress,
    this.paymentMethod,
    this.paymentStatus,
    this.note,
    this.voucherId,
    this.discountAmount = 0,
    this.orderType = 'offline',
    this.deliveryMethod,
    this.transactionId,
    this.paidAt,
    this.qrContent,
    this.transferContent,
    this.pointsUsed = 0,
    this.pointsEarned = 0,
    this.pointsDiscount = 0,
    this.customerPhone,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return Order(
      id: (json['order_id'] ?? json['id']).toString(),
      orderDate:
          TypeConverters.toLocalDateTime(
            json['created_at'] ?? json['orderDate'],
          ) ??
          DateTime.now(),
      totalAmount: TypeConverters.toDouble(
        json['final_amount'] ??
            json['total_after_discount'] ??
            json['discounted_total'] ??
            json['totalAmount'] ??
            json['total_amount'],
      ),
      customerName:
          (json['customer_name'] ?? json['customerName'] ?? 'Khách lẻ')
              .toString(),
      status:
          (json['order_status'] ?? json['orderStatus'] ?? json['status'] ?? '')
              .toString(),
      items: rawItems
          .whereType<Map>()
          .map((e) => OrderLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      customerId: TypeConverters.toNullableInt(
        json['customer_id'] ?? json['customerId'] ?? json['user_id'],
      ),
      shippingAddress: TypeConverters.toNullableString(
        json['shipping_address'] ?? json['shippingAddress'],
      ),
      paymentMethod: TypeConverters.toNullableString(
        json['payment_method'] ?? json['paymentMethod'] ?? json['method'],
      ),
      paymentStatus: TypeConverters.toNullableString(
        json['payment_status'] ?? json['paymentStatus'],
      ),
      note: TypeConverters.toNullableString(json['note']),
      voucherId: TypeConverters.toNullableInt(json['voucher_id']),
      discountAmount: TypeConverters.toDouble(json['discount_amount'] ?? 0),
      orderType: (json['order_type'] ?? json['orderType'] ?? 'offline')
          .toString(),
      deliveryMethod: TypeConverters.toNullableString(
        json['delivery_method'] ?? json['deliveryMethod'],
      ),
      transactionId: TypeConverters.toNullableString(
        json['transaction_id'] ?? json['transactionId'],
      ),
      paidAt: TypeConverters.toLocalDateTime(json['paid_at'] ?? json['paidAt']),
      qrContent: TypeConverters.toNullableString(
        json['qr_content'] ?? json['qrContent'] ?? json['fakeQrContent'],
      ),
      transferContent: TypeConverters.toNullableString(
        json['transfer_content'] ?? json['transferContent'],
      ),
      pointsUsed:
          TypeConverters.toNullableInt(
            json['points_used'] ?? json['pointsUsed'],
          ) ??
          0,
      pointsEarned:
          TypeConverters.toNullableInt(
            json['points_earned'] ?? json['pointsEarned'],
          ) ??
          0,
      pointsDiscount: TypeConverters.toDouble(
        json['points_discount'] ?? json['pointsDiscount'] ?? 0,
      ),
      customerPhone: TypeConverters.toNullableString(
        json['customer_phone'] ?? json['customerPhone'] ?? json['phone'],
      ),
    );
  }

  Map<String, dynamic> toJson({int? customerId, int? employeeId}) {
    return {
      'customer_id': customerId,
      'employee_id': employeeId,
      'order_type': orderType,
      'delivery_method': deliveryMethod,
      'status': status,
      'order_status': status,
      'payment_status': paymentStatus ?? 'paid',
      'shipping_address': shippingAddress,
      'payment_method': paymentMethod ?? 'cash',
      'note': note,
      'voucher_id': voucherId,
      'discount_amount': discountAmount,
      'transaction_id': transactionId,
      'paid_at': paidAt?.toIso8601String(),
      'qr_content': qrContent,
      'transfer_content': transferContent,
      'points_used': pointsUsed,
      'points_earned': pointsEarned,
      'points_discount': pointsDiscount,
      'customer_phone': customerPhone,
      'customer_name': customerName,
      'use_points': pointsUsed > 0,
      'points_to_use': pointsUsed,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }
}
