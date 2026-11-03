import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sieuthimini/services/api_service.dart';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Future<Map<String, dynamic>> cancel(http.Client client, {Duration? timeout}) => ApiService.cancelMyOrder(
  userId: 1, orderId: '5', reason: 'Lý do kiểm thử', client: client, requestTimeout: timeout,
);

void main() {
  test('Confirmed cancellation uses one PUT with correct endpoint/body', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'PUT');
      expect(request.url.path, '/orders/5/cancel');
      expect(jsonDecode(request.body)['reason'], 'Lý do kiểm thử');
      return jsonResponse({'success': true, 'data': {'order_id': 5, 'status': 'cancelled'}});
    });
    addTearDown(client.close);
    expect((await cancel(client))['status'], 'cancelled');
    expect(calls, 1);
  });
  for (final status in [400, 401, 403, 404, 409, 500]) {
    test('JSON HTTP $status preserves message/status and commit uncertainty', () async {
      final client = MockClient((_) async => jsonResponse({'success': false, 'message': 'Thông báo backend'}, status));
      addTearDown(client.close);
      try {
        await cancel(client);
        fail('Expected API failure');
      } on ApiException catch (error) {
        expect(error.statusCode, status);
        expect(error.message, contains('Thông báo backend'));
        expect(error.message, contains('HTTP $status'));
        expect(error.outcomeUnknown, status >= 500);
        if (status == 401) expect(error.message, contains('đăng nhập lại'));
      }
    });
  }
  for (final status in [200, 404, 500]) {
    test('HTML HTTP $status does not masquerade as loss of connection', () async {
      final client = MockClient((_) async => http.Response('<html>error</html>', status));
      addTearDown(client.close);
      await expectLater(cancel(client), throwsA(isA<ApiException>()
        .having((error) => error.statusCode, 'HTTP', status)
        .having((error) => error.message, 'message', contains('HTTP $status'))
        .having((error) => error.outcomeUnknown, 'uncertainty', status != 404)));
    });
  }
  for (final data in [<String, dynamic>{}, {'order_id': 5, 'status': 'pending'}, {'order_id': 6, 'status': 'cancelled'}]) {
    test('Invalid/mismatched success payload is never claimed cancelled: $data', () async {
      final client = MockClient((_) async => jsonResponse({'success': true, 'data': data}));
      addTearDown(client.close);
      await expectLater(cancel(client), throwsA(isA<ApiException>().having((error) => error.outcomeUnknown, 'uncertainty', isTrue)));
    });
  }
  test('Timeout is explicit and never retries the PUT', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return jsonResponse({'success': true, 'data': {'order_id': 5, 'status': 'cancelled'}});
    });
    addTearDown(client.close);
    await expectLater(cancel(client, timeout: const Duration(milliseconds: 1)), throwsA(isA<ApiException>()
      .having((error) => error.outcomeUnknown, 'uncertainty', isTrue)
      .having((error) => error.message, 'timeout', contains('Quá thời gian'))));
    expect(calls, 1);
  });
  test('Network failure is explicit and result is unknown', () async {
    final client = MockClient((_) async => throw http.ClientException('connection failed'));
    addTearDown(client.close);
    await expectLater(cancel(client), throwsA(isA<ApiException>()
      .having((error) => error.outcomeUnknown, 'uncertainty', isTrue)
      .having((error) => error.message, 'network', contains('không nhận được phản hồi'))));
  });
  test('Unexpected processing error is not labelled backend unavailable', () {
    expect(ApiService.requestErrorMessage(StateError('mock state')), contains('lỗi xử lý'));
    expect(ApiService.requestErrorMessage(const FormatException('mock')), contains('Không đọc được'));
    expect(ApiService.requestErrorMessage(TimeoutException('mock')), contains('thời gian chờ'));
  });
}
