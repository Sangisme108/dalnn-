import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/smart_sales_intent.dart';

void main() {
  for (final message in ['tận nhà ạ', 'tận nhà', 'tan nha a', 'đặt tôi tận nhà', 'đặt tận nhà', 'cho tôi đặt tận nhà', 'giao đến nhà cho tôi', 'ship về nhà', 'dat toi tan nha']) {
    test('Delivery phrasing begins checkout: $message', () {
      expect(SmartSalesIntent.wantsCheckout(message), isTrue);
    });
  }
  for (final message in ['tận nhà ạ', 'tận nhà', 'có đặt tôi tận nanf', 'có đặt tôi tận nhà', 'có giao tận nhà cho tôi', 'ok đặt cho tôi luôn']) {
    test('Long acceptance after delivery offer: $message', () {
      expect(SmartSalesIntent.acceptsCheckoutOffer(message, awaitingOffer: true), isTrue);
      expect(SmartSalesIntent.acceptsCheckoutOffer(message, awaitingOffer: false), isFalse);
    });
  }
  for (final message in ['có giao tận nhà không', 'có đặt hàng phí bao nhiêu', 'có thêm 5 dứa', 'có giao hàng bao lâu']) {
    test('Question/new item is not a checkout acceptance: $message', () {
      expect(SmartSalesIntent.acceptsCheckoutOffer(message, awaitingOffer: true), isFalse);
    });
  }
  for (final message in ['cho tôi mua luôn đi', 'mua luôn', 'chốt luôn', 'đặt luôn', 'cho mk mua luon']) {
    test('Buy now continues checkout: $message', () {
      expect(SmartSalesIntent.wantsCheckout(message), isTrue);
    });
  }
  for (final message in ['ok', 'đúng rồi', 'ừ', 'có', 'đồng ý', 'được rồi', 'dạ có ạ']) {
    test('Accepts only the current checkout offer: $message', () {
      expect(SmartSalesIntent.acceptsCheckoutOffer(message, awaitingOffer: true), isTrue);
      expect(SmartSalesIntent.acceptsCheckoutOffer(message, awaitingOffer: false), isFalse);
    });
  }
  for (final message in ['không', 'để sau', 'phí ship bao nhiêu', 'cho tôi thêm 2 dứa']) {
    test('New intent does not accept checkout offer: $message', () {
      expect(SmartSalesIntent.acceptsCheckoutOffer(message, awaitingOffer: true), isFalse);
    });
  }
  for (final message in [
    'Tôi muốn nấu lẩu cho 4 người', 'Mua mì tôm thì nên mua thêm gì?',
    'Hai loại sữa này khác nhau thế nào?', 'Hôm nay có gì giảm giá?',
    'Siêu thị có giao hàng không?', 'Shop có giao tận nhà chứ?',
    'Có được đổi trả không?', 'Thanh toán bằng gì?',
    'Chấm táo với sốt nào của shop ngon?', 'Phí ship bao nhiêu?',
  ]) {
    test('FAQ is advice, not purchase or checkout: $message', () {
      expect(SmartSalesIntent.needsAdvice(message), isTrue);
      expect(SmartSalesIntent.wantsPurchase(message), isFalse);
      expect(SmartSalesIntent.wantsCheckout(message), isFalse);
    });
  }
  for (final message in [
    'cho tôi 1 dứa được không', 'cho mk 5 dứa với', 'cho tôi 5 dưa hấu',
    'mk đặt dứa ạ', 'lấy 5 dứa', 'đặt 5 dứa', 'thêm 2 hộp dâu tây',
  ]) {
    test('Recognizes purchase: $message', () {
      expect(SmartSalesIntent.wantsPurchase(message), isTrue);
    });
  }
  for (final message in ['dưa hấu', 'không mua', 'k mua đâu', 'cho tôi xem dứa', '100k mua được gì']) {
    test('Does not purchase: $message', () {
      expect(SmartSalesIntent.wantsPurchase(message), isFalse);
    });
  }
  for (final message in ['đặt hàng', 'chốt đơn', 'giao tận nhà', 'đặt đơn hàng', 'dat hang']) {
    test('Recognizes checkout: $message', () {
      expect(SmartSalesIntent.wantsCheckout(message), isTrue);
    });
  }
  for (final message in ['mk đặt dứa ạ', 'xem đơn hàng', 'hủy đơn hàng', 'chi tiết đơn hàng']) {
    test('Does not checkout: $message', () {
      expect(SmartSalesIntent.wantsCheckout(message), isFalse);
    });
  }
}
