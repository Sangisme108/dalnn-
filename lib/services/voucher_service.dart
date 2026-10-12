import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/voucher.dart';
import 'api_service.dart';
import 'db_service.dart'; // Import để lấy token & user_id từ Hive

class VoucherService {
  static String get baseUrl => '${ApiService.baseUrl}/api/vouchers';
  static const Duration timeoutDuration = Duration(seconds: 10);

  // Helper: Get auth headers với token + user_id
  static Map<String, String> _getAuthHeaders(String token) {
    final settings = DBService.settings();
    final userId = settings.get('current_user_id') ?? '0';

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'x-user-id': userId.toString(),
    };
  }

  // 1. VALIDATE VOUCHER - Kiểm tra & tính giảm giá
  static Future<Map<String, dynamic>> validateVoucher({
    required String code,
    required double orderTotal,
    required int userId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/validate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'orderTotal': orderTotal,
              'userId': userId,
            }),
          )
          .timeout(
            timeoutDuration,
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true && json['voucher'] != null) {
          final voucherData = json['voucher'];
          return {
            'success': true,
            'data': {
              'id': voucherData['id'] ?? 0,
              'code': voucherData['code'] ?? '',
              'description': voucherData['description'],
              'discountAmount':
                  double.tryParse(
                    voucherData['discountAmount']?.toString() ?? '0',
                  ) ??
                  0.0,
              'finalTotal':
                  double.tryParse(
                    voucherData['finalTotal']?.toString() ?? '0',
                  ) ??
                  orderTotal,
            },
          };
        }
        return {'success': false, 'message': 'Dữ liệu voucher không hợp lệ'};
      } else {
        final json = jsonDecode(response.body);
        return {
          'success': false,
          'message': json['message'] ?? 'Lỗi validate voucher',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // 2. GET AVAILABLE VOUCHERS - Danh sách vouchers khả dụng
  static Future<List<Voucher>> getAvailableVouchers() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/available'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            timeoutDuration,
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        List<dynamic> data = json['data'] ?? [];
        return data.map((v) => Voucher.fromJson(v)).toList();
      }
      return [];
    } catch (e) {
      print('Lỗi lấy vouchers: $e');
      return [];
    }
  }

  // 3. GET VOUCHER BY CODE
  static Future<Voucher?> getVoucherByCode(String code) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/code/$code'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(
            timeoutDuration,
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return Voucher.fromJson(json['data']);
      }
      return null;
    } catch (e) {
      print('Lỗi lấy voucher: $e');
      return null;
    }
  }

  // 4. GET USER VOUCHERS - Danh sách vouchers của user
  static Future<List<Voucher>> getUserVouchers(int userId, String token) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/user/$userId'),
            headers: _getAuthHeaders(token),
          )
          .timeout(
            timeoutDuration,
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        List<dynamic> data = json['data'] ?? [];
        return data.map((v) => Voucher.fromJson(v)).toList();
      }
      return [];
    } catch (e) {
      print('Lỗi lấy vouchers của user: $e');
      return [];
    }
  }

  // 5. CLAIM VOUCHER - LÆ°u voucher vÃ o tÃ i khoáº£n khÃ¡ch hÃ ng
  static Future<Map<String, dynamic>> claimVoucher({
    required int voucherId,
    required String token,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/$voucherId/claim'),
            headers: _getAuthHeaders(token),
          )
          .timeout(
            timeoutDuration,
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      final json = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': json['message'] ?? 'ÄÃ£ lÆ°u voucher vÃ o tÃ i khoáº£n',
          'data': json['data'],
        };
      }

      return {
        'success': false,
        'message': json['message'] ?? 'KhÃ´ng thá»ƒ láº¥y mÃ£ voucher',
      };
    } catch (e) {
      return {'success': false, 'message': 'Lá»—i káº¿t ná»‘i: $e'};
    }
  }

  // ===== ADMIN FUNCTIONS =====

  // 5. CREATE VOUCHER - Tạo voucher mới
  static Future<Map<String, dynamic>> createVoucher({
    required String code,
    required String discountType,
    required double discountValue,
    String? description,
    double minOrderAmount = 0,
    double? maxDiscount,
    int? usageLimit,
    String? expiryDate,
    required String token,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(baseUrl),
            headers: _getAuthHeaders(token),
            body: jsonEncode({
              'code': code,
              'description': description,
              'discount_type': discountType,
              'discount_value': discountValue,
              'min_order_amount': minOrderAmount,
              'max_discount': maxDiscount,
              'usage_limit': usageLimit,
              'expiry_date': expiryDate,
            }),
          )
          .timeout(
            timeoutDuration,
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 201) {
        final json = jsonDecode(response.body);
        return {
          'success': true,
          'message': json['message'],
          'data': json['data'],
        };
      } else if (response.statusCode == 403) {
        return {'success': false, 'message': 'Bạn không có quyền tạo voucher'};
      } else {
        final json = jsonDecode(response.body);
        return {
          'success': false,
          'message': json['message'] ?? 'Lỗi tạo voucher',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // 6. GET ALL VOUCHERS (Admin)
  static Future<List<Voucher>> getAllVouchers(String token) async {
    try {
      final response = await http
          .get(Uri.parse(baseUrl), headers: _getAuthHeaders(token))
          .timeout(
            timeoutDuration,
            onTimeout: () {
              throw Exception('Request timeout - kiểm tra kết nối hoặc server');
            },
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        List<dynamic> data = json['data'] ?? [];
        return data.map((v) => Voucher.fromJson(v)).toList();
      }
      return [];
    } catch (e) {
      print('Lỗi lấy tất cả vouchers: $e');
      return [];
    }
  }

  // 7. UPDATE VOUCHER
  static Future<Map<String, dynamic>> updateVoucher({
    required int id,
    String? description,
    String? discountType,
    double? discountValue,
    double? minOrderAmount,
    double? maxDiscount,
    int? usageLimit,
    String? expiryDate,
    String? status,
    required String token,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/$id'),
            headers: _getAuthHeaders(token),
            body: jsonEncode({
              'description': description,
              'discount_type': discountType,
              'discount_value': discountValue,
              'min_order_amount': minOrderAmount,
              'max_discount': maxDiscount,
              'usage_limit': usageLimit,
              'expiry_date': expiryDate,
              'status': status,
            }),
          )
          .timeout(
            timeoutDuration,
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return {'success': true, 'message': json['message']};
      } else {
        final json = jsonDecode(response.body);
        return {
          'success': false,
          'message': json['message'] ?? 'Lỗi cập nhật voucher',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // 8. DELETE VOUCHER
  static Future<Map<String, dynamic>> deleteVoucher(
    int id,
    String token,
  ) async {
    try {
      final response = await http
          .delete(Uri.parse('$baseUrl/$id'), headers: _getAuthHeaders(token))
          .timeout(
            timeoutDuration,
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return {'success': true, 'message': json['message']};
      } else {
        final json = jsonDecode(response.body);
        return {
          'success': false,
          'message': json['message'] ?? 'Lỗi xóa voucher',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  // 9. GET VOUCHER USAGE (Admin)
  static Future<List<Map<String, dynamic>>> getVoucherUsage(
    int id,
    String token,
  ) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/$id/usage'), headers: _getAuthHeaders(token))
          .timeout(
            timeoutDuration,
            onTimeout: () {
              throw Exception('Request timeout');
            },
          );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        List<dynamic> data = json['data'] ?? [];
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Lỗi lấy lịch sử dùng voucher: $e');
      return [];
    }
  }
}
