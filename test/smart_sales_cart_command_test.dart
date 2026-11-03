import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/smart_sales_cart_command.dart';

void main() {
  for (final message in ['xóa giỏ hàng ạ', 'xoá giỏ hàng', 'xóa hết giỏ hàng', 'xoa gio hang', 'bỏ tất cả trong giỏ', 'xóa hết']) {
    test('Clear cart: $message', () {
      expect(SmartSalesCartCommand.removal(message)?.clearAll, isTrue);
    });
  }
  const names = {'1': 'Dứa (Thơm)', '2': 'Dưa hấu', '3': 'Dâu tây', '4': 'Trà xanh C2 hương chanh'};
  for (final entry in {'xóa dâu tây': '3', 'bỏ dưa hấu ra': '2', 'xóa dứa': '1', 'xoa dau tay': '3', 'xóa sản phẩm dâu tây trong giỏ': '3', 'xóa sp 2': '2'}.entries) {
    test('Remove only requested cart item: ${entry.key}', () {
      final command = SmartSalesCartCommand.removal(entry.key)!;
      expect(command.clearAll, isFalse);
      expect(SmartSalesCartCommand.matchProducts(command.target, names), [entry.value]);
    });
  }
  for (final message in ['không xóa dứa', 'đừng xóa giỏ', 'hủy đơn hàng', 'xem giỏ hàng', 'hủy']) {
    test('Not a removal: $message', () {
      expect(SmartSalesCartCommand.removal(message), isNull);
    });
  }
  test('Unspecified or ambiguous product asks for selection', () {
    final unspecified = SmartSalesCartCommand.removal('xóa sản phẩm trong giỏ')!;
    expect(unspecified.clearAll, isFalse);
    expect(unspecified.target, isEmpty);
    expect(SmartSalesCartCommand.matchProducts('dua', names), ['1', '2']);
    expect(SmartSalesCartCommand.matchProducts('không tồn tại', names), isEmpty);
  });
  test('Only explicit thêm increments quantity', () {
    expect(SmartSalesCartCommand.wantsIncrement('lấy 5 dứa'), isFalse);
    expect(SmartSalesCartCommand.wantsIncrement('cho tôi 5 dứa'), isFalse);
    expect(SmartSalesCartCommand.wantsIncrement('thêm 5 dứa'), isTrue);
  });
}
