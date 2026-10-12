import 'package:hive/hive.dart';

part 'voucher.g.dart';

@HiveType(typeId: 5) // Chọn typeId chưa dùng
class Voucher extends HiveObject {
  @HiveField(0)
  int id;

  @HiveField(1)
  String code;

  @HiveField(2)
  String? description;

  @HiveField(3)
  String discountType; // 'fixed' hoặc 'percent'

  @HiveField(4)
  double discountValue;

  @HiveField(5)
  double minOrderAmount;

  @HiveField(6)
  double? maxDiscount;

  @HiveField(7)
  int? usageLimit;

  @HiveField(8)
  int usedCount;

  @HiveField(9)
  DateTime? expiryDate;

  @HiveField(10)
  String status; // 'active' hoặc 'inactive'

  @HiveField(11)
  DateTime createdAt;

  Voucher({
    required this.id,
    required this.code,
    this.description,
    required this.discountType,
    required this.discountValue,
    this.minOrderAmount = 0,
    this.maxDiscount,
    this.usageLimit,
    this.usedCount = 0,
    this.expiryDate,
    this.status = 'active',
    required this.createdAt,
  });

  // Tính toán discount amount
  double calculateDiscount(double orderTotal) {
    double discount = 0;

    if (discountType == 'fixed') {
      discount = discountValue;
    } else if (discountType == 'percent') {
      discount = orderTotal * (discountValue / 100);
      if (maxDiscount != null && discount > maxDiscount!) {
        discount = maxDiscount!;
      }
    }

    // Không được giảm quá tổng tiền
    discount = discount > orderTotal ? orderTotal : discount;

    return discount;
  }

  // Kiểm tra voucher còn hợp lệ không
  bool isValid(double orderTotal) {
    // Kiểm tra status
    if (status != 'active') return false;

    // Kiểm tra hết hạn
    if (expiryDate != null && expiryDate!.isBefore(DateTime.now())) {
      return false;
    }

    // Kiểm tra giới hạn dùng
    if (usageLimit != null && usedCount >= usageLimit!) {
      return false;
    }

    // Kiểm tra đơn tối thiểu
    if (orderTotal < minOrderAmount) {
      return false;
    }

    return true;
  }

  // Từ JSON
  factory Voucher.fromJson(Map<String, dynamic> json) {
    return Voucher(
      id: json['voucher_id'] ?? json['id'] ?? 0,
      code: json['code'] ?? '',
      description: json['description'],
      discountType: json['discount_type'] ?? 'fixed',
      discountValue: double.tryParse(json['discount_value'].toString()) ?? 0,
      minOrderAmount:
          double.tryParse(json['min_order_amount']?.toString() ?? '0') ?? 0,
      maxDiscount: json['max_discount'] != null
          ? double.tryParse(json['max_discount'].toString())
          : null,
      usageLimit: json['usage_limit'],
      usedCount: json['used_count'] ?? 0,
      expiryDate: json['expiry_date'] != null
          ? DateTime.parse(json['expiry_date'].toString())
          : null,
      status: json['status'] ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
    );
  }

  // Sang JSON
  Map<String, dynamic> toJson() {
    return {
      'voucher_id': id,
      'code': code,
      'description': description,
      'discount_type': discountType,
      'discount_value': discountValue,
      'min_order_amount': minOrderAmount,
      'max_discount': maxDiscount,
      'usage_limit': usageLimit,
      'used_count': usedCount,
      'expiry_date': expiryDate?.toIso8601String(),
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  String toString() =>
      'Voucher($code - $discountValue${discountType == 'percent' ? '%' : ' VND'})';
}
