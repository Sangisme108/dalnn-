import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/order.dart';
import '../models/product.dart';
import '../models/product_review.dart';
import '../models/work_shift.dart';
import '../models/employee_schedule_day.dart';
import '../models/user.dart';
import '../models/inventory_item.dart';
import 'db_service.dart';
import '../utils/constants.dart';
import '../utils/type_converters.dart';

// Ca làm / tổng hợp nhân viên có thể chậm hơn API thông thường.
Duration get _shiftTimeout =>
    const Duration(seconds: AppConstants.shiftTimeoutSeconds);

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class ApiService {
  static const Duration _timeout = Duration(
    seconds: AppConstants.apiTimeoutSeconds,
  );
  static int? _currentUserId;

  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return _normalizeBaseUrl(configured);

    final override = AppConstants.apiBaseUrlOverride;
    if (override != null && override.isNotEmpty) {
      return _normalizeBaseUrl(override);
    }

    if (kIsWeb) return 'http://localhost:3000';

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Chỉ máy ảo Android: 10.0.2.2 = localhost của máy host
        return 'http://10.0.2.2:3000';
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iPhone thật không truy cập được localhost của Mac.
        // Dùng mDNS .local để chạy ổn định khi cắm dây hoặc cùng Wi-Fi.
        return AppConstants.iosDefaultApiBaseUrl;
      }
    } catch (_) {}

    return 'http://localhost:3000';
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) return trimmed.substring(0, trimmed.length - 1);
    return trimmed;
  }

  static String connectionErrorMessage(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('timeout') ||
        msg.contains('timed out') ||
        msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('clientexception')) {
      return 'Không kết nối được backend ($baseUrl). '
          'Kiểm tra backend đang chạy (npm run dev). '
          'Android emulator dùng 10.0.2.2, iOS simulator dùng localhost, '
          'iPhone thật dùng ${AppConstants.iosDefaultApiBaseUrl} hoặc '
          '--dart-define=API_BASE_URL=http://<IP-Mac>:3000.';
    }
    return 'Email hoặc mật khẩu không đúng';
  }

  static Uri _uri(String path) => Uri.parse('$baseUrl$path');

  static String resolveBackendUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('/uploads/')) return '$baseUrl$trimmed';
    return trimmed;
  }

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  static String? get _authToken {
    try {
      final token = DBService.settings().get('auth_token');
      return token is String && token.isNotEmpty ? token : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> get _authHeaders => {
    ..._headers,
    if (_authToken != null) 'Authorization': 'Bearer $_authToken',
  };

  static Map<String, String> get _userHeaders => {
    ..._authHeaders,
    if ((_currentUserId ?? DBService.currentUserId()) != null)
      'x-user-id': (_currentUserId ?? DBService.currentUserId()).toString(),
  };

  static Map<String, String> _userHeadersFor(int userId) => {
    ..._authHeaders,
    'x-user-id': userId.toString(),
  };

  static Map<String, String> _adminHeaders(int adminUserId) => {
    ..._authHeaders,
    'x-user-id': adminUserId.toString(),
  };

  static dynamic _decode(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 400) {
      final message = body is Map
          ? (body['error'] ??
                    body['message'] ??
                    'Lỗi API ${response.statusCode}')
                .toString()
          : 'Lỗi API ${response.statusCode}';
      throw ApiException(message);
    }
    if (body is Map && body['success'] == false) {
      throw ApiException((body['message'] ?? 'API trả về lỗi').toString());
    }
    return body;
  }

  static List<dynamic> _dataList(dynamic body) {
    if (body is Map && body['data'] is List) return body['data'] as List;
    if (body is List) return body;
    return const [];
  }

  static Map<String, dynamic> _dataMap(dynamic body) {
    if (body is Map && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map) return Map<String, dynamic>.from(body);
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> login(
    String identifier,
    String password,
  ) async {
    final response = await http
        .post(
          _uri('/api/auth/login'),
          headers: _headers,
          body: jsonEncode({'identifier': identifier, 'password': password}),
        )
        .timeout(_timeout);
    final body = _decode(response);
    final user = Map<String, dynamic>.from((body as Map)['user'] as Map);
    final token = body['token']?.toString();
    if (token != null && token.isNotEmpty) {
      await DBService.settings().put('auth_token', token);
    }
    _currentUserId = TypeConverters.toNullableInt(
      user['user_id'] ?? user['userId'],
    );
    return user;
  }

  static Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required String phone,
    String? address,
  }) async {
    final response = await http
        .post(
          _uri('/api/auth/register'),
          headers: _headers,
          body: jsonEncode({
            'full_name': fullName,
            'email': email,
            'password': password,
            'phone': phone,
            'address': address,
          }),
        )
        .timeout(_timeout);
    _decode(response);
  }

  static Future<Map<String, dynamic>> forgotPasswordEmail(String email) async {
    final response = await http
        .post(
          _uri('/api/auth/forgot-password/email'),
          headers: _headers,
          body: jsonEncode({'email': email}),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<Map<String, dynamic>> forgotPasswordPhone(String phone) async {
    final response = await http
        .post(
          _uri('/api/auth/forgot-password/phone'),
          headers: _headers,
          body: jsonEncode({'phone': phone}),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<String> verifyPasswordResetOtp({
    required String identifier,
    required String type,
    required String otp,
  }) async {
    final response = await http
        .post(
          _uri('/api/auth/verify-otp'),
          headers: _headers,
          body: jsonEncode({
            'identifier': identifier,
            'type': type,
            'otp': otp,
          }),
        )
        .timeout(_timeout);
    final body = _dataMap(_decode(response));
    return (body['reset_token'] ?? '').toString();
  }

  static Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    final response = await http
        .post(
          _uri('/api/auth/reset-password'),
          headers: _headers,
          body: jsonEncode({
            'reset_token': resetToken,
            'new_password': newPassword,
          }),
        )
        .timeout(_timeout);
    _decode(response);
  }

  static Future<List<User>> fetchUsers() async {
    final response = await http.get(_uri('/api/users')).timeout(_timeout);
    final body = _decode(response);
    return _dataList(
      body,
    ).map((e) => User.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<User> createUser(User user) async {
    final response = await http
        .post(
          _uri('/api/users'),
          headers: _authHeaders,
          body: jsonEncode(user.toJson()),
        )
        .timeout(_timeout);
    final body = _decode(response);
    return User.fromJson(_dataMap(body));
  }

  static Future<User> updateUser(int userId, User user) async {
    final response = await http
        .put(
          _uri('/api/users/$userId'),
          headers: _authHeaders,
          body: jsonEncode(user.toJson()),
        )
        .timeout(_timeout);
    final body = _decode(response);
    return User.fromJson(_dataMap(body));
  }

  static Future<User> updateUserProfile({
    required int userId,
    required String fullName,
    required String phone,
    required String address,
    String? password,
  }) async {
    final response = await http
        .put(
          _uri('/api/users/$userId/profile'),
          headers: _userHeadersFor(userId),
          body: jsonEncode({
            'full_name': fullName,
            'phone': phone.isEmpty ? null : phone,
            'address': address.isEmpty ? null : address,
            if (password != null && password.isNotEmpty) 'password': password,
          }),
        )
        .timeout(_timeout);
    return User.fromJson(_dataMap(_decode(response)));
  }

  static Future<Map<String, dynamic>> fetchEmployeeSummary(int userId) async {
    final response = await http
        .get(_uri('/api/users/$userId/employee-summary'))
        .timeout(_shiftTimeout);
    return _dataMap(_decode(response));
  }

  static Future<EmployeeScheduleMonth> fetchEmployeeScheduleMonth({
    required int employeeId,
    required int year,
    required int month,
  }) async {
    final response = await http
        .get(
          _uri(
            '/api/employee-schedules/employee/$employeeId/month?year=$year&month=$month',
          ),
        )
        .timeout(_shiftTimeout);
    final body = _dataMap(_decode(response));
    return EmployeeScheduleMonth.fromJson(body);
  }

  static Future<EmployeeScheduleDay> setEmployeeDayStatus({
    required int employeeId,
    required String workDate,
    required String dayStatus,
    String? note,
    int? setBy,
  }) async {
    final response = await http
        .put(
          _uri('/api/employee-schedules/employee/$employeeId/day'),
          headers: _headers,
          body: jsonEncode({
            'work_date': workDate,
            'day_status': dayStatus,
            if (note != null) 'note': note,
            if (setBy != null) 'set_by': setBy,
          }),
        )
        .timeout(_shiftTimeout);
    return EmployeeScheduleDay.fromJson(_dataMap(_decode(response)));
  }

  static Future<List<Map<String, dynamic>>> fetchScheduleOverviewMonth({
    required int year,
    required int month,
  }) async {
    final response = await http
        .get(
          _uri(
            '/api/employee-schedules/overview/month?year=$year&month=$month',
          ),
        )
        .timeout(_shiftTimeout);
    final body = _dataMap(_decode(response));
    final list = body['employees'];
    if (list is List) {
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  static Future<List<WorkShift>> fetchEmployeeShiftsForMonth({
    required int employeeId,
    required int year,
    required int month,
  }) async {
    final response = await http
        .get(
          _uri('/api/work-shifts/employee/$employeeId?year=$year&month=$month'),
        )
        .timeout(_shiftTimeout);
    final body = _decode(response);
    return _dataList(body)
        .map((e) => WorkShift.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<WorkShift>> fetchWorkShifts({
    int? employeeId,
    String status = 'all',
    String dateFilter = 'all',
  }) async {
    final query = <String, String>{
      if (employeeId != null) 'employee_id': employeeId.toString(),
      if (status != 'all') 'status': status,
      if (dateFilter != 'all') 'date_filter': dateFilter,
    };
    final uri = _uri('/api/work-shifts').replace(queryParameters: query);
    final response = await http.get(uri).timeout(_shiftTimeout);
    final body = _decode(response);
    return _dataList(body)
        .map((e) => WorkShift.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<Map<String, dynamic>> startWorkShift(int employeeId) async {
    final response = await http
        .post(
          _uri('/api/work-shifts/start'),
          headers: _headers,
          body: jsonEncode({'employee_id': employeeId}),
        )
        .timeout(_shiftTimeout);
    return _dataMap(_decode(response));
  }

  static Future<Map<String, dynamic>> endWorkShift(int employeeId) async {
    final response = await http
        .post(
          _uri('/api/work-shifts/end'),
          headers: _headers,
          body: jsonEncode({'employee_id': employeeId}),
        )
        .timeout(_shiftTimeout);
    return _dataMap(_decode(response));
  }

  static Future<void> deleteUser(int userId) async {
    final response = await http
        .delete(_uri('/api/users/$userId'), headers: _authHeaders)
        .timeout(_timeout);
    _decode(response);
  }

  static Future<List<Map<String, dynamic>>> fetchCategories() async {
    final response = await http.get(_uri('/api/categories')).timeout(_timeout);
    final body = _decode(response);
    return _dataList(
      body,
    ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> createCategory(String name) async {
    final response = await http
        .post(
          _uri('/api/categories'),
          headers: _headers,
          body: jsonEncode({'category_name': name}),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<List<Product>> fetchProducts() async {
    final response = await http.get(_uri('/api/products')).timeout(_timeout);
    final body = _decode(response);
    return _dataList(body)
        .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<Product> createProduct(Product product) async {
    final response = await http
        .post(
          _uri('/api/products'),
          headers: _headers,
          body: jsonEncode(product.toJson()),
        )
        .timeout(_timeout);
    return Product.fromJson(_dataMap(_decode(response)));
  }

  static Future<Product> updateProduct(Product product) async {
    final response = await http
        .put(
          _uri('/api/products/${product.id}'),
          headers: _headers,
          body: jsonEncode(product.toJson()),
        )
        .timeout(_timeout);
    return Product.fromJson(_dataMap(_decode(response)));
  }

  static Future<void> deleteProduct(String productId) async {
    final response = await http
        .delete(_uri('/api/products/$productId'))
        .timeout(_timeout);
    _decode(response);
  }

  static Future<Map<String, dynamic>> scanProductCode(String code) async {
    final response = await http
        .get(_uri('/api/products/scan/${Uri.encodeComponent(code)}'))
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<bool> productCodeExists(String code) async {
    final response = await http
        .get(_uri('/api/products/check-code/${Uri.encodeComponent(code)}'))
        .timeout(_timeout);
    final body = _dataMap(_decode(response));
    return body['exists'] == true;
  }

  static Future<String> generateProductCode({
    int? categoryId,
    String? prefix,
  }) async {
    final response = await http
        .post(
          _uri('/api/products/generate-code'),
          headers: _headers,
          body: jsonEncode({
            if (categoryId != null) 'category_id': categoryId,
            if (prefix != null && prefix.isNotEmpty) 'prefix': prefix,
          }),
        )
        .timeout(_timeout);
    final body = _dataMap(_decode(response));
    return (body['code'] ?? '').toString();
  }

  static Future<String> uploadProductImage(String filePath) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/uploads/product-image'),
    );
    request.files.add(await http.MultipartFile.fromPath('image', filePath));
    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    final body = _dataMap(_decode(response));
    final rawUrl = (body['url'] ?? body['image_url'] ?? '').toString();
    if (rawUrl.isEmpty) {
      throw ApiException('Backend không trả về URL ảnh');
    }
    return resolveBackendUrl(rawUrl);
  }

  static Future<List<Order>> fetchOrders() async {
    final response = await http.get(_uri('/api/orders')).timeout(_timeout);
    final body = _decode(response);
    return _dataList(
      body,
    ).map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<List<Order>> fetchOnlineOrders() async {
    final response = await http
        .get(_uri('/api/orders/online'), headers: _userHeaders)
        .timeout(_timeout);
    final body = _decode(response);
    return _dataList(
      body,
    ).map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<List<Order>> fetchPurchaseHistory({int? customerId}) async {
    final path = customerId == null
        ? '/api/orders/history'
        : '/api/orders/history/$customerId';
    final response = await http
        .get(_uri(path), headers: _userHeaders)
        .timeout(_timeout);
    final body = _decode(response);
    return _dataList(
      body,
    ).map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchMyOrders(int userId) async {
    final response = await http
        .get(_uri('/my-orders'), headers: _userHeadersFor(userId))
        .timeout(_timeout);
    final body = _decode(response);
    return _dataList(
      body,
    ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchPendingOrders(
    int employeeId,
  ) async {
    final response = await http
        .get(_uri('/orders/pending'), headers: _userHeadersFor(employeeId))
        .timeout(_timeout);
    final body = _decode(response);
    return _dataList(
      body,
    ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<Map<String, dynamic>> confirmOrder({
    required int employeeId,
    required String orderId,
  }) async {
    final response = await http
        .put(
          _uri('/orders/$orderId/confirm'),
          headers: _userHeadersFor(employeeId),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<Map<String, dynamic>> rejectOrder({
    required int employeeId,
    required String orderId,
    String? reason,
  }) async {
    final response = await http
        .put(
          _uri('/orders/$orderId/reject'),
          headers: _userHeadersFor(employeeId),
          body: jsonEncode({
            if (reason != null && reason.trim().isNotEmpty)
              'reason': reason.trim(),
          }),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<Map<String, dynamic>> markOrderReceived({
    required int userId,
    required String orderId,
  }) async {
    final response = await http
        .put(
          _uri('/orders/$orderId/received'),
          headers: _userHeadersFor(userId),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<Map<String, dynamic>> cancelMyOrder({
    required int userId,
    required String orderId,
    required String reason,
  }) async {
    final response = await http
        .put(
          _uri('/orders/$orderId/cancel'),
          headers: _userHeadersFor(userId),
          body: jsonEncode({'reason': reason.trim()}),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<Order> fetchOrderDetail(String orderId) async {
    final response = await http
        .get(_uri('/api/orders/$orderId'), headers: _userHeaders)
        .timeout(_timeout);
    return Order.fromJson(_dataMap(_decode(response)));
  }

  static Future<Order> updateOrderStatus(String orderId, String status) async {
    final response = await http
        .patch(
          _uri('/api/orders/$orderId/status'),
          headers: _userHeaders,
          body: jsonEncode({'status': status}),
        )
        .timeout(_timeout);
    return Order.fromJson(_dataMap(_decode(response)));
  }

  static Future<Order> createOrder(
    Order order, {
    int? customerId,
    int? employeeId,
  }) async {
    final response = await http
        .post(
          _uri('/api/orders'),
          headers: _headers,
          body: jsonEncode(
            order.toJson(customerId: customerId, employeeId: employeeId),
          ),
        )
        .timeout(_timeout);
    return Order.fromJson(_dataMap(_decode(response)));
  }

  static Future<Order> createOrderWithVoucher(
    Order order, {
    int? customerId,
    int? employeeId,
    int? voucherId,
    double discountAmount = 0,
    int? userId,
  }) async {
    final orderData = order.toJson(
      customerId: customerId,
      employeeId: employeeId,
    );
    // Thêm voucher info vào payload
    if (voucherId != null) {
      orderData['voucher_id'] = voucherId;
    }
    if (discountAmount > 0) {
      orderData['discount_amount'] = discountAmount;
    }
    if (userId != null) {
      orderData['user_id'] = userId;
    }

    final response = await http
        .post(
          _uri('/api/orders'),
          headers: _headers,
          body: jsonEncode(orderData),
        )
        .timeout(_timeout);
    return Order.fromJson(_dataMap(_decode(response)));
  }

  static Future<List<ProductReview>> fetchProductReviews(
    String productId,
  ) async {
    final response = await http
        .get(_uri('/api/reviews/products/$productId'))
        .timeout(_timeout);
    final body = _decode(response);
    return _dataList(body)
        .map((e) => ProductReview.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<Map<String, dynamic>> createReview({
    String? orderId,
    required String productId,
    required int rating,
    String? comment,
    int? customerId,
  }) async {
    final payload = <String, dynamic>{
      'product_id': int.tryParse(productId) ?? productId,
      'rating': rating,
      'comment': comment,
    };
    if (orderId != null && orderId.trim().isNotEmpty) {
      payload['order_id'] = int.tryParse(orderId) ?? orderId;
    }

    final response = await http
        .post(
          _uri('/api/reviews'),
          headers: customerId == null
              ? _userHeaders
              : _userHeadersFor(customerId),
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<double> getAverageRating(String productId) async {
    final reviews = await fetchProductReviews(productId);
    return ProductReview.averageRating(reviews);
  }

  static Future<int> getTotalReviews(String productId) async {
    final reviews = await fetchProductReviews(productId);
    return reviews.length;
  }

  static Future<List<Map<String, dynamic>>> fetchInventoryLogs() async {
    final response = await http
        .get(_uri('/api/inventory/logs'))
        .timeout(_timeout);
    final body = _decode(response);
    return _dataList(
      body,
    ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<List<InventoryItem>> fetchInventoryItems() async {
    final response = await http
        .get(_uri('/api/inventory/items'))
        .timeout(_timeout);
    final body = _decode(response);
    return _dataList(body)
        .map((e) => InventoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<InventoryItem> createInventoryItem(InventoryItem item) async {
    final response = await http
        .post(
          _uri('/api/inventory/items'),
          headers: _headers,
          body: jsonEncode(item.toJson()),
        )
        .timeout(_timeout);
    return InventoryItem.fromJson(_dataMap(_decode(response)));
  }

  static Future<InventoryItem> updateInventoryItem(InventoryItem item) async {
    final response = await http
        .put(
          _uri('/api/inventory/items/${item.id}'),
          headers: _headers,
          body: jsonEncode(item.toJson()),
        )
        .timeout(_timeout);
    return InventoryItem.fromJson(_dataMap(_decode(response)));
  }

  static Future<void> importInventory({
    required String inventoryItemId,
    required int employeeId,
    required int quantity,
    required double importPrice,
    String? note,
  }) async {
    final response = await http
        .post(
          _uri('/api/inventory/import'),
          headers: _headers,
          body: jsonEncode({
            'inventory_item_id': inventoryItemId,
            'employee_id': employeeId,
            'quantity': quantity,
            'import_price': importPrice,
            'note': note,
          }),
        )
        .timeout(_timeout);
    _decode(response);
  }

  static Future<double?> fetchInventoryImportPrice(String barcode) async {
    final response = await http
        .get(_uri('/api/inventory/cost/$barcode'))
        .timeout(_timeout);
    final body = _dataMap(_decode(response));
    final value = body['import_price'];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static Future<void> adjustInventory({
    required String inventoryItemId,
    required int employeeId,
    required int actualQuantity,
    String? note,
  }) async {
    final response = await http
        .post(
          _uri('/api/inventory/adjust'),
          headers: _headers,
          body: jsonEncode({
            'inventory_item_id': inventoryItemId,
            'employee_id': employeeId,
            'actual_quantity': actualQuantity,
            'note': note,
          }),
        )
        .timeout(_timeout);
    _decode(response);
  }

  static Future<void> exportInventory({
    required String inventoryItemId,
    String? productId,
    required int employeeId,
    required int quantity,
    String? note,
  }) async {
    final response = await http
        .post(
          _uri('/api/inventory/export'),
          headers: _headers,
          body: jsonEncode({
            'inventory_item_id': inventoryItemId,
            'product_id': productId == null ? null : int.tryParse(productId),
            'employee_id': employeeId,
            'quantity': quantity,
            'note': note,
          }),
        )
        .timeout(_timeout);
    _decode(response);
  }

  static Future<Map<String, int>> fetchCart(int userId) async {
    final response = await http
        .get(_uri('/api/carts'), headers: _userHeadersFor(userId))
        .timeout(_timeout);
    final body = _dataMap(_decode(response));
    final items = (body['items'] as List?) ?? const [];
    return {
      for (final item in items)
        (item as Map)['product_id'].toString(): (item['quantity'] ?? 0) as int,
    };
  }

  static Future<void> saveCart(int userId, Map<String, int> cart) async {
    final items = <Map<String, int>>[];
    for (final entry in cart.entries) {
      final productId = int.tryParse(entry.key);
      if (productId != null && entry.value > 0) {
        items.add({'product_id': productId, 'quantity': entry.value});
      }
    }
    final response = await http
        .put(
          _uri('/api/carts/update'),
          headers: _userHeadersFor(userId),
          body: jsonEncode({'items': items}),
        )
        .timeout(_timeout);
    _decode(response);
  }

  static Future<Map<String, int>> addCartItem(
    int userId,
    String productId,
    int quantity,
  ) async {
    final response = await http
        .post(
          _uri('/api/carts/add'),
          headers: _userHeadersFor(userId),
          body: jsonEncode({
            'product_id': int.tryParse(productId) ?? productId,
            'quantity': quantity,
          }),
        )
        .timeout(_timeout);
    final body = _dataMap(_decode(response));
    final items = (body['items'] as List?) ?? const [];
    return {
      for (final item in items)
        (item as Map)['product_id'].toString(): (item['quantity'] ?? 0) as int,
    };
  }

  static Future<Map<String, int>> removeCartItem(
    int userId,
    String productId,
  ) async {
    final request = http.Request('DELETE', _uri('/api/carts/remove'))
      ..headers.addAll(_userHeadersFor(userId))
      ..body = jsonEncode({'product_id': int.tryParse(productId) ?? productId});
    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    final body = _dataMap(_decode(response));
    final items = (body['items'] as List?) ?? const [];
    return {
      for (final item in items)
        (item as Map)['product_id'].toString(): (item['quantity'] ?? 0) as int,
    };
  }

  static Future<Map<String, dynamic>> validateVoucher({
    required String code,
    required double orderTotal,
    required int userId,
  }) async {
    final response = await http
        .post(
          _uri('/api/vouchers/validate'),
          headers: _userHeadersFor(userId),
          body: jsonEncode({
            'code': code.trim().toUpperCase(),
            'orderTotal': orderTotal,
            'userId': userId,
          }),
        )
        .timeout(_timeout);
    final body = _decode(response);
    if (body is Map && body['voucher'] is Map) {
      return Map<String, dynamic>.from(body['voucher'] as Map);
    }
    return _dataMap(body);
  }

  static Future<Map<String, dynamic>> createVnpayPayment({
    required int userId,
    required int orderId,
    String? bankCode,
  }) async {
    final response = await http
        .post(
          _uri('/api/payments/vnpay/create'),
          headers: _userHeadersFor(userId),
          body: jsonEncode({
            'order_id': orderId,
            if (bankCode != null && bankCode.isNotEmpty) 'bank_code': bankCode,
          }),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<Map<String, dynamic>> fetchOrderPaymentStatus({
    required int userId,
    required int orderId,
  }) async {
    final response = await http
        .get(
          _uri('/api/orders/$orderId/payment-status'),
          headers: _userHeadersFor(userId),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<Map<String, dynamic>> fetchOrderPaymentStatusByCode(
    String orderCode,
  ) async {
    final encodedCode = Uri.encodeComponent(orderCode.trim());
    final response = await http
        .get(_uri('/api/orders/status/$encodedCode'), headers: _headers)
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<Map<String, dynamic>> confirmBankTransferManual({
    required int userId,
    required int orderId,
  }) async {
    final response = await http
        .post(
          _uri('/api/payments/bank-transfer/manual-confirm'),
          headers: _userHeadersFor(userId),
          body: jsonEncode({'order_id': orderId}),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<Map<String, dynamic>> addCustomerPoints({
    required String customerName,
    required String phone,
    required double amount,
    required int employeeId,
    String? orderId,
  }) async {
    final response = await http
        .post(
          _uri('/api/points/add'),
          headers: _userHeadersFor(employeeId),
          body: jsonEncode({
            'customerName': customerName,
            'phone': phone,
            'amount': amount,
            'employeeId': employeeId,
            if (orderId != null && orderId.trim().isNotEmpty)
              'orderId': int.tryParse(orderId) ?? orderId,
          }),
        )
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<Map<String, dynamic>> fetchCustomerPoints({
    required String phone,
    double? amountAfterVoucher,
  }) async {
    final query = <String, String>{'phone': phone};
    if (amountAfterVoucher != null) {
      query['amount_after_voucher'] = amountAfterVoucher.toStringAsFixed(0);
    }
    final uri = Uri.parse(
      '$baseUrl/api/points/customer',
    ).replace(queryParameters: query);
    final response = await http.get(uri, headers: _headers).timeout(_timeout);
    final decoded = _decode(response);
    return decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
  }

  static Future<Order> checkoutOnlineOrder({
    required int userId,
    required String deliveryMethod,
    required String paymentMethod,
    String? shippingAddress,
    DateTime? pickupTime,
    String? voucherCode,
    String? note,
  }) async {
    final response = await http
        .post(
          _uri('/api/orders/checkout'),
          headers: _userHeadersFor(userId),
          body: jsonEncode({
            'delivery_method': deliveryMethod,
            'payment_method': paymentMethod,
            if (shippingAddress != null) 'shipping_address': shippingAddress,
            if (pickupTime != null)
              'pickup_time': pickupTime.toUtc().toIso8601String(),
            if (voucherCode != null && voucherCode.trim().isNotEmpty)
              'voucher_code': voucherCode.trim().toUpperCase(),
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          }),
        )
        .timeout(_timeout);
    return Order.fromJson(_dataMap(_decode(response)));
  }

  static Future<Map<String, dynamic>> fetchRevenueReport(
    int adminUserId,
  ) async {
    final response = await http
        .get(_uri('/api/reports/revenue'), headers: _adminHeaders(adminUserId))
        .timeout(_timeout);
    return _dataMap(_decode(response));
  }

  static Future<List<Map<String, dynamic>>> fetchProductPerformanceReport(
    int adminUserId,
  ) async {
    final response = await http
        .get(
          _uri('/api/reports/product-performance'),
          headers: _adminHeaders(adminUserId),
        )
        .timeout(_timeout);
    final body = _decode(response);
    return _dataList(
      body,
    ).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> fetchProductPerformanceDashboard(
    int adminUserId, {
    required String range,
    String? month,
  }) async {
    final query = <String, String>{'range': range};
    if (month != null && month.isNotEmpty) query['month'] = month;
    final uri = _uri(
      '/api/performance/dashboard',
    ).replace(queryParameters: query);
    final response = await http
        .get(uri, headers: _adminHeaders(adminUserId))
        .timeout(_timeout);
    debugPrint(
      '[performance] GET $uri -> ${response.statusCode} (${response.bodyBytes.length} bytes)',
    );
    final responseBody = utf8.decode(response.bodyBytes);
    debugPrint(
      '[performance] response ${responseBody.substring(0, responseBody.length > 800 ? 800 : responseBody.length)}',
    );
    return _dataMap(_decode(response));
  }
}
