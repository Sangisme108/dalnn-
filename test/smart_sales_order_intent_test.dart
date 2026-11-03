import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/smart_sales_order_intent.dart';

void main() {
  for (final message in ['đơn số 7 hủy giúp tôi 3 chai xốt trứng muối ạ', 'hủy đơn 7', 'hủy đơn hàng số 7', 'hủy đơn #7', 'don so 7 huy giup toi']) {
    test('Identifies order number, not item quantity: $message', () {
      expect(SmartSalesOrderIntent.orderId(message), '7');
      expect(SmartSalesOrderIntent.isCancellation(message), isTrue);
    });
  }
  test('Bare cancel stays a cancel intent for current order context', () {
    expect(SmartSalesOrderIntent.isCancellation('hủy'), isTrue);
    expect(SmartSalesOrderIntent.orderId('hủy'), isNull);
  });
  for (final message in ['xem đơn hàng đã hủy', 'không hủy đơn 7', 'đừng hủy đơn 7', 'xem đơn 7']) {
    test('Does not cancel from viewing/refusal: $message', () {
      expect(SmartSalesOrderIntent.isCancellation(message), isFalse);
    });
  }
  test('Distinguishes cancelling items from the whole order', () {
    expect(SmartSalesOrderIntent.refersToOrderItems('đơn số 7 hủy giúp tôi 3 chai xốt trứng muối'), isTrue);
    expect(SmartSalesOrderIntent.refersToOrderItems('hủy toàn bộ đơn 7'), isFalse);
    expect(SmartSalesOrderIntent.refersToOrderItems('hủy đơn 7'), isFalse);
  });
}
