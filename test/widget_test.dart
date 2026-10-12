import 'package:flutter_test/flutter_test.dart';
import 'package:sieuthimini/models/product.dart';
import 'package:sieuthimini/models/work_shift.dart';
import 'package:sieuthimini/repositories/work_shift_repository.dart';
import 'package:sieuthimini/services/api_service.dart';

void main() {
  test('API base URL and product JSON mapping are valid', () {
    expect(ApiService.baseUrl, isNotEmpty);

    final product = Product.fromJson({
      'product_id': 1,
      'product_name': 'Táo đỏ',
      'price': 20000,
      'stock': 10,
      'category_id': 2,
      'category_name': 'Trái cây',
    });

    expect(product.id, '1');
    expect(product.name, 'Táo đỏ');
    expect(product.price, 20000);
    expect(product.stockQuantity, 10);
    expect(product.categoryId, 2);
  });

  test('WorkShift display picks open shift first', () {
    final summary = {
      'current_shift': {
        'shift_id': 1,
        'employee_id': 2,
        'shift_date': '2026-05-17',
        'start_time': '08:00:00',
        'end_time': null,
        'status': 'working',
      },
      'latest_shift': {
        'shift_id': 1,
        'employee_id': 2,
        'shift_date': '2026-05-17',
        'start_time': '08:00:00',
        'end_time': null,
        'status': 'working',
      },
      'work_status': 'working',
    };

    final display = WorkShiftRepository.getDisplayShift(summary);
    expect(display.isWorking, isTrue);
    expect(display.badgeLabel, 'Đang làm');
    expect(display.displayShift?.startTime, '08:00:00');
  });

  test('WorkShift display uses latest when no open shift', () {
    final summary = {
      'current_shift': null,
      'latest_shift': {
        'shift_id': 2,
        'employee_id': 2,
        'shift_date': '2026-05-16',
        'start_time': '07:30:00',
        'end_time': '15:00:00',
        'status': 'completed',
      },
      'work_status': 'off',
    };

    final display = WorkShiftDisplay.fromSummary(summary);
    expect(display.isWorking, isFalse);
    expect(display.badgeLabel, 'Đã kết thúc');
    expect(display.displayShift?.endTime, '15:00:00');
  });
}
