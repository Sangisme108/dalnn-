/// Centralized constants for the application
/// Avoids duplication of constant values across screens

class AppConstants {
  // Inventory constants
  static const int minStockThreshold = 50;

  // API timeout
  static const int apiTimeoutSeconds = 15;
  static const int shiftTimeoutSeconds = 15;
  static const int checkoutTimeoutSeconds = 12;
  static const double maxPaymentAmount = 99999999.99;
  static const String maxPaymentAmountMessage =
      'Số tiền thanh toán tối đa là 99.999.999,99 VND';

  /// Ưu tiên truyền khi chạy:
  /// flutter run --dart-define=API_BASE_URL=http://IP_MAC:3000
  ///
  /// Nếu không truyền dart-define:
  /// - Android emulator dùng http://10.0.2.2:3000 trong ApiService.
  /// - iPhone thật dùng IP Wi-Fi của Mac vì một số máy không ổn định với .local.
  static const String? apiBaseUrlOverride = null;
  static const String macBonjourApiBaseUrl =
      'http://MacBook-Pro-cua-Mac-3.local:3000';
  static const String iosDefaultApiBaseUrl = 'http://192.168.100.79:3000';

  // Hive box names
  static const String productsBox = 'products';
  static const String usersBox = 'users';
  static const String ordersBox = 'orders';
  static const String settingsBox = 'settings';
  static const String cartsBox = 'carts';
  static const String productImagesBox = 'product_images';
  static const String inventoryProductsBox = 'inventory_products';
  static const String inventoryHistoryBox = 'inventory_history_box';
  static const String workShiftSummariesBox = 'work_shift_summaries';

  // Cache schema
  static const int cacheSchemaVersion = 3;
  static const bool forceUseLocalProductSeed = false;
}
