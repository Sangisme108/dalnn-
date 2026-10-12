import 'package:hive/hive.dart';
import '../utils/type_converters.dart';

part 'user.g.dart';

@HiveType(typeId: 1)
class User extends HiveObject {
  @HiveField(13)
  int? userId;

  @HiveField(0)
  String email;

  @HiveField(1)
  String password;

  @HiveField(2)
  String role; // 'owner' or 'staff'

  @HiveField(3)
  String fullName;

  @HiveField(4)
  int birthYear;

  @HiveField(5)
  String phone;

  @HiveField(6)
  String address;

  @HiveField(7)
  String gender;

  @HiveField(8)
  DateTime? startDate;

  @HiveField(9)
  String? avatarPath; // local file path or asset

  @HiveField(10)
  String status;

  @HiveField(11)
  int points;

  @HiveField(12)
  DateTime? createdAt;

  @HiveField(14)
  String? membershipCode;

  User({
    this.userId,
    required this.email,
    required this.password,
    required this.role,
    this.fullName = '',
    this.birthYear = 0,
    this.phone = '',
    this.address = '',
    this.gender = '',
    this.startDate,
    this.avatarPath,
    this.status = 'active',
    this.points = 0,
    this.createdAt,
    this.membershipCode,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: TypeConverters.toNullableInt(json['user_id'] ?? json['id']),
      email: (json['email'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      role: (json['role_name'] ?? json['role'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['fullName'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      status: (json['status'] ?? 'active').toString(),
      points: TypeConverters.toNullableInt(json['points']) ?? 0,
      membershipCode: TypeConverters.toNullableString(
        json['membership_code'] ?? json['membershipCode'],
      ),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'full_name': fullName,
      'user_id': userId,
      'email': email,
      'phone': phone.isEmpty ? null : phone,
      'password': password,
      'address': address.isEmpty ? null : address,
      'role': role,
      'status': status,
    };
  }
}
