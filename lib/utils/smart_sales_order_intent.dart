import 'smart_sales_cart_command.dart';

class SmartSalesOrderIntent {
  static String? orderId(String message) {
    final hash = RegExp(r'#\s*(\d+)').firstMatch(message);
    if (hash != null) return hash.group(1);
    return RegExp(r'\bdon\s*(?:hang\s*)?(?:(?:so|ma)\s*)?(\d+)\b')
        .firstMatch(SmartSalesCartCommand.normalize(message))?.group(1);
  }

  static bool isCancellation(String message) {
    final text = SmartSalesCartCommand.normalize(message);
    if (RegExp(r'\b(khong|ko|k|dung|chua)\s+(huy|xoa|bo)\b|\bdon.*\bda huy\b|\bxem\b').hasMatch(text)) return false;
    return RegExp(r'\b(huy|xoa|bo)\b').hasMatch(text) &&
        (text.contains('don') || orderId(message) != null || text == 'huy' || text == 'huy di');
  }

  static bool refersToOrderItems(String message) {
    final text = SmartSalesCartCommand.normalize(message);
    if (RegExp(r'\b(toan bo|ca don|het don)\b').hasMatch(text)) return false;
    return RegExp(r'\b(chai|hop|goi|cai|qua|kg|can|mon|san pham|sp)\b').hasMatch(text);
  }
}
