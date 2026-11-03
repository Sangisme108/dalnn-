

import 'package:flutter/material.dart';

import '../models/product.dart';
import '../screens/order_detail_screen.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../utils/smart_sales_intent.dart';
import '../utils/smart_sales_cart_command.dart';
import '../utils/smart_sales_order_intent.dart';

/// Nút trợ lý bán hàng nổi, có thể kéo đến vị trí phù hợp trên màn hình.
class SmartSalesChatButton extends StatefulWidget {
  const SmartSalesChatButton({super.key});

  @override
  State<SmartSalesChatButton> createState() => _SmartSalesChatButtonState();
}

class _SmartSalesChatButtonState extends State<SmartSalesChatButton> {
  Offset _position = const Offset(18, 112);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Positioned(
      right: _position.dx,
      bottom: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) => setState(() {
          _position = Offset(
            (_position.dx - details.delta.dx).clamp(8, size.width - 68),
            (_position.dy - details.delta.dy).clamp(8, size.height - 68),
          );
        }),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const SmartSalesChatSheet(),
            ),
            borderRadius: BorderRadius.circular(32),
            child: Ink(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Color(0xFF008563),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12)],
              ),
              child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 30),
            ),
          ),
        ),
      ),
    );
  }
}

class SmartSalesChatSheet extends StatefulWidget {
  const SmartSalesChatSheet({super.key});

  @override
  State<SmartSalesChatSheet> createState() => _SmartSalesChatSheetState();
}

class _SmartSalesChatSheetState extends State<SmartSalesChatSheet> {
  final _input = TextEditingController();
  static final List<_ChatMessage> _messages = [
    const _ChatMessage(false, 'Dạ SmartSales xin chào! Bạn cần tìm sản phẩm, thêm giỏ hàng hay tra cứu đơn ạ?'),
  ];
  static Product? _selectedProduct;
  static List<Product> _lastSuggestedProducts = [];
  static _CheckoutStep _checkoutStep = _CheckoutStep.none;
  static String? _shippingAddress;
  static String? _phone;
  static String? _paymentMethod;
  static Product? _pendingProduct;
  static int? _pendingQuantity;
  static String _pendingCartMode = 'set';
  static bool _awaitingRemovalTarget = false;
  static String? _selectedOrderId;
  static String? _cancelOrderId;
  static String? _cancelReason;
  static _OrderCancelStep _orderCancelStep = _OrderCancelStep.none;

  void _resetCancellation() {
    _cancelOrderId = null;
    _cancelReason = null;
    _orderCancelStep = _OrderCancelStep.none;
  }

  Future<_ChatMessage?> _handleOrderCancellation(String text) async {
    final userId = DBService.currentUserId();
    final queryId = SmartSalesOrderIntent.orderId(text);
    final cancelRequest = SmartSalesOrderIntent.isCancellation(text);
    final shortText = SmartSalesCartCommand.normalize(text);
    if (queryId != null && cancelRequest && SmartSalesOrderIntent.refersToOrderItems(text)) _resetCancellation();
    if (queryId != null && _cancelOrderId != null && queryId != _cancelOrderId) _resetCancellation();
    if (_orderCancelStep != _OrderCancelStep.none &&
        SmartSalesCartCommand.removal(text) != null && !shortText.contains('gio')) {
      final id = _cancelOrderId;
      _resetCancellation();
      return _ChatMessage(false, 'Đơn #$id đã được đặt, hiện chưa thể bỏ riêng sản phẩm. Mình chưa thay đổi đơn hay giỏ hàng. Nếu muốn hủy toàn bộ, bạn nhắn “hủy đơn $id”.');
    }
    if (_orderCancelStep != _OrderCancelStep.none &&
        (SmartSalesCartCommand.removal(text) != null || _needsSalesAdvice(text) ||
         _isBudgetQuestion(text) || SmartSalesIntent.wantsCheckout(text) ||
         (_wantsToBuy(text) && _orderCancelStep != _OrderCancelStep.reason) ||
         (_wantsOrders(text) && !cancelRequest))) {
      _resetCancellation();
      _selectedOrderId = null;
      return null;
    }
    if (_orderCancelStep == _OrderCancelStep.scope &&
        (_confirms(text) || (cancelRequest && !SmartSalesOrderIntent.refersToOrderItems(text)))) {
      _orderCancelStep = _OrderCancelStep.reason;
      return _ChatMessage(false, 'Bạn cho mình biết lý do hủy toàn bộ đơn #$_cancelOrderId nhé.');
    }
    if (_orderCancelStep == _OrderCancelStep.scope && !cancelRequest) {
      final id = _cancelOrderId;
      _resetCancellation();
      _selectedOrderId = null;
      if (shortText == 'khong' || shortText == 'thoi' || SmartSalesOrderIntent.refersToOrderItems(text)) {
        return _ChatMessage(false, 'Đơn #$id được giữ nguyên. Hiện chưa hỗ trợ xóa riêng sản phẩm trong đơn đã đặt.');
      }
      return null;
    }
    if (_orderCancelStep == _OrderCancelStep.reason && (queryId == null || queryId == _cancelOrderId)) {
      if (shortText == 'thoi' || shortText == 'khong huy' || shortText == 'khong') {
        _resetCancellation();
        return const _ChatMessage(false, 'Mình đã dừng yêu cầu hủy; đơn hàng được giữ nguyên.');
      }
      if (cancelRequest || _confirms(text)) return _ChatMessage(false, 'Mình cần lý do hủy đơn #$_cancelOrderId, ví dụ “đặt nhầm” hoặc “không còn nhu cầu”.');
      if (text.trim().length > 255) return const _ChatMessage(false, 'Bạn nhập lý do hủy tối đa 255 ký tự nhé.');
      _cancelReason = text.trim();
      _orderCancelStep = _OrderCancelStep.confirm;
      return _ChatMessage(false, 'Bạn xác nhận hủy TOÀN BỘ đơn #$_cancelOrderId với lý do “$_cancelReason” đúng không ạ? Các món trong đơn này đều sẽ bị hủy.');
    }
    if (_orderCancelStep == _OrderCancelStep.confirm) {
      if (_confirms(text)) {
        final id = _cancelOrderId!;
        final reason = _cancelReason!;
        _resetCancellation();
        if (userId == null) return const _ChatMessage(false, 'Bạn đăng nhập tài khoản để hủy đơn nhé.');
        try {
          await ApiService.cancelMyOrder(userId: userId, orderId: id, reason: reason);
        } on ApiException catch (error) {
          if (!error.outcomeUnknown) return _ChatMessage(false, 'Không hủy được đơn #$id: ${error.message}');
          // Chỉ đọc lại trạng thái. Tuyệt đối không tự gửi lại PUT hủy đơn
          // khi lần đầu có thể đã thành công nhưng bị mất phản hồi.
          try {
            final orders = await ApiService.fetchMyOrders(userId);
            final matches = orders.where((order) => '${order['order_id'] ?? order['id']}' == id).toList();
            if (matches.isNotEmpty && _isCancelledOrder(matches.first)) {
              _selectedOrderId = null;
              return _ChatMessage(false, 'Đã kiểm tra lại hệ thống: đơn #$id đã hủy thành công.');
            }
            final lastStatus = matches.isEmpty ? '' : ' Trạng thái kiểm tra gần nhất: ${_orderStatusLabel(matches.first)}.';
            return _ChatMessage(false, 'Chưa xác nhận hủy thành công đơn #$id: ${error.message}$lastStatus Bạn kiểm tra mục Đơn hàng trước khi gửi lại yêu cầu hủy.');
          } catch (_) {
            return _ChatMessage(false, '${error.message}\nHiện chưa kiểm tra lại được đơn #$id. Bạn kiểm tra mục Đơn hàng trước khi gửi lại yêu cầu hủy.');
          }
        }
        _selectedOrderId = null;
        return _ChatMessage(false, 'Đã hủy đơn #$id. Lý do: $reason. Bạn có thể kiểm tra tại mục Đơn hàng.');
      }
      _resetCancellation();
      return const _ChatMessage(false, 'Mình chưa hủy đơn. Bạn có thể gửi lại yêu cầu nếu muốn thay đổi.');
    }
    if (!cancelRequest) {
      if (queryId == null && !_wantsOrders(text)) _selectedOrderId = null;
      return null;
    }
    // Hủy trong checkout đang tạo chỉ dừng tạo đơn, không hủy đơn cũ.
    if (queryId == null && (_checkoutStep != _CheckoutStep.none || _pendingProduct != null)) return null;
    _pendingProduct = null;
    _pendingQuantity = null;
    _awaitingCheckoutOffer = false;
    if (userId == null) return const _ChatMessage(false, 'Bạn đăng nhập tài khoản để tra và hủy đơn nhé.');
    final allOrders = await ApiService.fetchMyOrders(userId);
    final id = queryId ?? _selectedOrderId;
    if (id == null) {
      final active = allOrders.where((order) => !_isCancelledOrder(order) && _orderStatusLabel(order) != 'hoàn thành').toList();
      return _ChatMessage(false, active.isEmpty ? 'Hiện không có đơn phù hợp để hủy.' : 'Bạn muốn hủy đơn nào? Nhắn “hủy đơn 7” hoặc nhấn vào đơn để mở chi tiết.', orders: active);
    }
    final matches = allOrders.where((order) => '${order['order_id'] ?? order['id']}' == id).toList();
    if (matches.isEmpty) return _ChatMessage(false, 'Mình không tìm thấy đơn #$id trong tài khoản của bạn.');
    final order = matches.single;
    if (_isCancelledOrder(order) || _orderStatusLabel(order) == 'hoàn thành') return _ChatMessage(false, 'Đơn #$id hiện ${_orderStatusLabel(order)}, nên không thực hiện hủy thêm.', orders: [order]);
    _selectedOrderId = id;
    _cancelOrderId = id;
    if (SmartSalesOrderIntent.refersToOrderItems(text)) {
      _orderCancelStep = _OrderCancelStep.scope;
      return _ChatMessage(false, 'Mình đã xác định đơn #$id. Hiện hệ thống chỉ hỗ trợ hủy toàn bộ đơn đã đặt, chưa hỗ trợ bỏ riêng vài sản phẩm. Bạn muốn hủy TOÀN BỘ đơn #$id không ạ? Mình chưa hủy hay sửa món nào.', orders: [order]);
    }
    _orderCancelStep = _OrderCancelStep.reason;
    return _ChatMessage(false, 'Bạn cho mình biết lý do hủy đơn #$id nhé.', orders: [order]);
  }
  static bool _awaitingCheckoutOffer = false;
  bool _loading = false;
  ScrollController? _scrollController;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _scrollController;
      if (controller?.hasClients ?? false) {
        controller!.animateTo(controller.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  double? _maxPrice(String text) {
    final money = RegExp(r'(\d+(?:[.,]\d+)?)\s*(triệu|trieu|tr|nghìn|nghin|ngàn|ngan|k|vnđ|vnd|đồng|dong|đ)(?![\p{L}\p{N}])', caseSensitive: false, unicode: true).firstMatch(text);
    if (money != null) {
      final amount = double.tryParse(money.group(1)!.replaceAll(',', '.'));
      if (amount == null) return null;
      final unit = money.group(2)!.toLowerCase();
      if (const {'tr', 'triệu', 'trieu'}.contains(unit)) return amount * 1000000;
      if (const {'k', 'nghìn', 'nghin', 'ngàn', 'ngan'}.contains(unit)) return amount * 1000;
      return amount;
    }
    if (RegExp(r'\d\s*(kg|cân|can|kí|ký|hộp|hop|chai|gói|goi)(?![\p{L}\p{N}])', caseSensitive: false, unicode: true).hasMatch(text)) return null;
    final match = RegExp(r'(?:dưới|duoi|tối đa|max|tầm|khoảng|ngân sách|có|giá|<)\s*(\d+(?:[.,]\d+)?)\s*(k|nghìn|ngan|vnđ|vnd)?', caseSensitive: false).firstMatch(text) ??
        RegExp(r'(\d+(?:[.,]\d+)?)\s*(k|nghìn|ngan|vnđ|vnd)\b', caseSensitive: false).firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (value == null) return null;
    final unit = match.group(2)?.toLowerCase();
    // Số có hậu tố k/nghìn là nghìn đồng; các số khác là VNĐ.
    return (unit == 'k' || unit == 'nghìn' || unit == 'ngan') ? value * 1000 : value;
  }

  List<Product> _searchProducts(List<Product> products, String text) {
    final query = text.toLowerCase();
    final maxPrice = _maxPrice(query);
    final wantsFruit = query.contains('hoa quả') || query.contains('hoa qua') || query.contains('trái cây');
    const ignored = {'tôi', 'muốn', 'ăn', 'có', 'loại', 'nào', 'dưới', 'trên', 'sản', 'phẩm', 'cho', 'mình', 'với', 'giá', 'tầm', 'khoảng', 'ngân', 'sách', 'tiền', 'chi', 'tiết', 'giới', 'thiệu', 'thông', 'mô', 'tả', 'công', 'dụng', 'đặt', 'dat', 'giao', 'ship', 'tận', 'tan', 'nhà', 'nha', 'giúp', 'giup'};
    final keywords = query.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((word) => word.length >= 3 && !ignored.contains(word)).toList();
    if (maxPrice != null && _isBudgetQuestion(query)) {
      final budgetMatches = products.where((item) {
        if (!item.isActive || item.stockQuantity <= 0 || item.price > maxPrice) return false;
        return !wantsFruit || (item.categoryName ?? '').toLowerCase().contains('trái cây');
      }).toList()..sort((a, b) => a.price.compareTo(b.price));
      return budgetMatches.take(6).toList();
    }
    // Ưu tiên cả tên sản phẩm; không chọn xốt chỉ vì trùng một từ như
    // "tây" trong câu khách yêu cầu dâu tây.
    final exactMatches = products.where((item) => item.name.trim().length > 2 && query.contains(item.name.trim().toLowerCase())).toList();
    if (exactMatches.isNotEmpty) return exactMatches.take(6).toList();
    return products.where((item) {
      if (maxPrice != null && item.price > maxPrice) return false;
      if (wantsFruit) return (item.categoryName ?? '').toLowerCase().contains('trái cây');
      if (maxPrice != null && keywords.isEmpty) return true;
      return keywords.any((word) => item.name.toLowerCase().contains(word));
    }).take(6).toList();
  }

  bool _isBudgetQuestion(String text) =>
      _maxPrice(text) != null &&
      (RegExp(r'ngân sách|ngan sach|tầm|tam|khoảng|khoang|dưới|duoi|mua.*(gì|gi|được|duoc|đc)|có.*\d|co.*\d|tiền|tien', caseSensitive: false).hasMatch(text) ||
       RegExp(r'\d\s*(k|nghìn|nghin|ngàn|ngan|tr|triệu|trieu|vnđ|vnd|đồng|dong)(?![\p{L}\p{N}])', caseSensitive: false, unicode: true).hasMatch(text));

  int? _quantity(String text) {
    if (_isBudgetQuestion(text)) return null;
    return int.tryParse(
      RegExp(r'\b(\d+)\s*(?:cái|hộp|chai|gói|kg|kí|ký|cân)?', caseSensitive: false)
              .firstMatch(text)
              ?.group(1) ??
          '',
    );
  }

  String? _requestedUnit(String text) {
    final match = RegExp(r'(?:^|\s|\d)(kg|kilogram|kí|ký|cân|can|hộp|hop|chai|gói|goi|cái|cai|lon|túi|tui|quả|qua|trái|trai|thùng|thung)(?![\p{L}\p{N}])', caseSensitive: false, unicode: true).firstMatch(text);
    return match == null ? null : _canonicalUnit(match.group(1)!);
  }

  String _canonicalUnit(String unit) {
    final value = unit.trim().toLowerCase();
    if (const {'kg', 'kilogram', 'kí', 'ký', 'cân', 'can'}.contains(value)) return 'kg';
    if (value == 'hop') return 'hộp';
    if (value == 'goi') return 'gói';
    if (value == 'cai') return 'cái';
    if (value == 'tui') return 'túi';
    if (value == 'qua') return 'quả';
    if (value == 'trai') return 'trái';
    if (value == 'thung') return 'thùng';
    return value;
  }

  bool _wantsToBuy(String text) => SmartSalesIntent.wantsPurchase(text);

  bool _wantsIntroduction(String text) => RegExp(r'giới thiệu|thông tin|mô tả|công dụng|chi tiết|chi tiet', caseSensitive: false).hasMatch(text);

  bool _isInformationRequest(String text) => RegExp(
    r'(?:^|\s)(?:giá|gia)(?:\s|$)|bao nhiêu|bao nhieu|tồn kho|ton kho|còn hàng|con hang|hết hàng|het hang|khối lượng|khoi luong|dung tích|dung tich|\bml\b|\bgam\b|\bgram\b|nặng|nang|hạn dùng|han dung|hạn sử dụng|han su dung|thành phần|thanh phan|công dụng|cong dung|dùng để|dung de|mô tả|mo ta|chi tiết|chi tiet|so sánh|so sanh',
    caseSensitive: false,
  ).hasMatch(text);

  bool _referencesCurrentProduct(String text) => RegExp(
    r'cái này|cai nay|chai này|chai nay|món này|mon nay|loại này|loai nay|cái đó|cai do|loại đó|loai do',
    caseSensitive: false,
  ).hasMatch(text);

  bool _isAmbiguousContainerQuestion(String text) => RegExp(
    r'(một|mot|1)\s*(chai|hộp|hop|gói|goi).*bao nhiêu|(chai|hộp|hop|gói|goi).*bao nhiêu\s*\??$',
    caseSensitive: false,
  ).hasMatch(text);

  bool _abandonsPendingPurchase(String text) => RegExp(
    r'thôi|thoi|không mua|khong mua|\bk\s+mua|\bko\s+mua|khỏi|khoi|hủy|huy',
    caseSensitive: false,
  ).hasMatch(text);

  bool _rejectsPurchase(String text) => RegExp(
    r'(^|\s)(k|ko|không|khong|thôi|thoi)\s*(tôi\s*)?(k\s*)?(mua|lấy|lay|đặt|dat)',
    caseSensitive: false,
  ).hasMatch(text);

  bool _wantsOrders(String text) => SmartSalesOrderIntent.orderId(text) != null || RegExp(
    r'xem\s*(các\s*)?đơn|đơn\s*(hàng|của|vừa|mới)|mã\s*đơn|đơn\s*số|lịch sử mua|tra cứu đơn',
    caseSensitive: false,
  ).hasMatch(text);

  bool _asksLatestOrder(String text) => RegExp(
    r'đơn\s*(vừa|mới).*?(số|mã)|(?:số|mã).*?đơn\s*(vừa|mới)|đơn\s*số\s*mấy',
    caseSensitive: false,
  ).hasMatch(text);

  bool _wantsCancelledOrders(String text) => RegExp(
    r'đơn\s*(hàng\s*)?(đã\s*)?hủy|đơn\s*(hàng\s*)?(đã\s*)?huy|đơn\s*bị\s*từ chối|đơn\s*(đã\s*)?cancel',
    caseSensitive: false,
  ).hasMatch(text);

  String _money(Object? value) => '${(double.tryParse(value?.toString() ?? '') ?? 0).toStringAsFixed(0)} VNĐ';

  bool _isSmallTalk(String text) => RegExp(
    r'thời tiết|thoi tiet|bao nhiêu.*[+*/]|yêu anh|yeu anh|yêu em|yeu em|đùa|dua|kể chuyện|ke chuyen|bạn là ai|ban la ai',
    caseSensitive: false,
  ).hasMatch(text);

  // Câu hỏi cần suy luận/tư vấn, không phải chỉ tìm tên sản phẩm. Gemini sẽ
  // nhận toàn bộ danh mục thật để trả lời tự nhiên mà không bịa hàng của shop.
  bool _needsSalesAdvice(String text) => SmartSalesIntent.needsAdvice(text);

  List<String> _suggestedCategories(List<Product> products) => products
      .map((product) => product.categoryName?.trim() ?? '')
      .where((name) => name.isNotEmpty)
      .toSet()
      .take(5)
      .toList();

  Future<String> _dynamicFallback({
    required String message,
    required Map<String, dynamic> toolResult,
    required String localFallback,
  }) async {
    try {
      return await ApiService.askGeminiReply(message, toolResult: toolResult);
    } catch (_) {
      // Khi Gemini tạm quá tải, vẫn có câu trả lời an toàn để khách không bị treo chat.
      return localFallback;
    }
  }

  Future<void> _showOrderDetail(Map<String, dynamic> order) async {
    final id = order['order_id'] ?? order['id'] ?? '';
    if (id.toString().isEmpty) return;
    final navigator = Navigator.of(context);
    try {
      final detail = await ApiService.fetchOrderDetail(id.toString());
      if (!mounted) return;
      navigator.pop();
      await navigator.push(MaterialPageRoute(builder: (_) => OrderDetailScreen(order: detail)));
    } catch (_) {
      if (mounted) setState(() => _messages.add(const _ChatMessage(false, 'Dạ chưa mở được chi tiết đơn. Bạn thử lại giúp shop nhé.')));
      _scrollToLatest();
    }
  }

  bool _confirms(String text) {
    var value = text.trim().toLowerCase().replaceAll(RegExp(r'[.!?,]'), '');
    value = value.replaceFirst(RegExp(r'^(dạ|da)\s+'), '');
    value = value.replaceFirst(RegExp(r'\s+(ạ|a|nha|nhé|nhe)$'), '').trim();
    if (RegExp(r'(^|\s)(k|ko|không|khong|chưa|chua|hủy|huy)(\s|$)', caseSensitive: false).hasMatch(value)) {
      return false;
    }
    const replies = {
      'xác nhận', 'xac nhan', 'đồng ý', 'dong y', 'đúng', 'đúng rồi',
      'dung', 'dung roi', 'ok', 'oke', 'okay', 'ok rồi', 'ok roi',
      'được', 'được rồi', 'duoc', 'duoc roi', 'đc', 'rồi', 'roi',
      'vâng', 'vang', 'ừ', 'uh', 'yes', 'chốt', 'chốt đơn',
    };
    if (replies.contains(value)) return true;
    // Cho phép các câu ngắn tự nhiên như "ok em chốt" hay "được nha",
    // nhưng không coi một câu dài có chữ "đc" là lời xác nhận.
    const fillers = {'ạ', 'a', 'nha', 'nhé', 'nhe', 'em', 'anh', 'chị', 'chi', 'shop', 'mình', 'minh'};
    const affirmativeWords = {
      'xác', 'nhận', 'xac', 'nhan', 'đồng', 'ý', 'dong', 'y', 'đúng', 'dung',
      'ok', 'oke', 'okay', 'được', 'duoc', 'đc', 'rồi', 'roi', 'vâng', 'vang',
      'ừ', 'uh', 'yes', 'chốt',
    };
    final words = value.split(RegExp(r'\s+')).where((word) => !fillers.contains(word)).toList();
    return words.isNotEmpty && words.every(affirmativeWords.contains);
  }

  bool _isCancelledOrder(Map<String, dynamic> order) {
    final status = '${order['status'] ?? order['order_status'] ?? ''}'.toLowerCase();
    return status.contains('cancel') ||
        status.contains('hủy') ||
        status.contains('huy') ||
        status.contains('reject') ||
        status.contains('từ chối');
  }

  String _orderStatusLabel(Map<String, dynamic> order) {
    final status = '${order['status'] ?? order['order_status'] ?? ''}'.toLowerCase();
    if (status.contains('cancel')) return 'đã hủy';
    if (status.contains('reject')) return 'đã từ chối';
    if (status.contains('pending') || status.contains('waiting')) return 'chờ xác nhận';
    if (status.contains('confirm')) return 'đã xác nhận';
    if (status.contains('shipping')) return 'đang giao';
    if (status.contains('completed')) return 'hoàn thành';
    return status.isEmpty ? 'đang xử lý' : status;
  }

  Future<String> _addPendingProduct(String confirmation) async {
    final product = _pendingProduct!;
    final quantity = _pendingQuantity!;
    final cartMode = _pendingCartMode;
    // Tiêu thụ xác nhận một lần. Một tin nhắn "ok" tiếp theo không được
    // thực hiện lại hành động cũ, kể cả khi kết nối thất bại.
    _pendingProduct = null;
    _pendingQuantity = null;
    final userId = DBService.currentUserId();
    if (userId == null) return 'Bạn đăng nhập tài khoản để shop hỗ trợ thêm giỏ hàng nhé ạ.';
    if (quantity > product.stockQuantity) return 'Dạ ${product.name} hiện chỉ còn ${product.stockQuantity} ${product.unit}. Bạn muốn điều chỉnh số lượng không ạ?';
    try {
      // Gửi yêu cầu đã xác nhận cho backend kiểm tra và thực hiện. Hạn mức
      // Gemini chỉ ảnh hưởng tư vấn, không chặn giao dịch đã rõ của khách.
      final result = await ApiService.askSmartSalesChat(
        userId: userId,
        message: confirmation,
        candidateProductIds: [product.id],
        confirmedProductId: product.id,
        confirmedQuantity: quantity,
        cartMode: cartMode,
      );
      final answer = result['answer']?.toString().trim();
      final action = result['action'];
      final added = action is Map && action['type'] == 'addToCart';
      if (added) {
        _selectedProduct = product;
        _pendingProduct = null;
        _pendingQuantity = null;
        _awaitingCheckoutOffer = true;
        try {
          final cart = await ApiService.fetchCart(userId);
          final email = DBService.currentUserEmail();
          if (email != null) await DBService.carts().put(email, cart);
        } catch (_) {
          // Kết quả thao tác đã thành công; lỗi làm mới cache không được
          // biến thành báo thêm giỏ thất bại và khiến khách thêm lại.
        }
        return '${answer?.isNotEmpty == true ? answer : 'Đã thêm $quantity ${product.unit} ${product.name} vào giỏ hàng.'}\n\nBạn muốn đặt giao tận nhà luôn không ạ?';
      }
      return (answer?.isNotEmpty ?? false)
          ? answer!
          : (added
              ? '✅ Shop đã thêm $quantity ${product.unit} ${product.name} vào giỏ hàng.'
              : 'Shop chưa thêm được sản phẩm. Bạn có thể kiểm tra giỏ và gửi lại yêu cầu thêm hàng.');
    } on ApiException catch (error) {
      return 'Chưa thêm được hàng: ${error.message}';
    } catch (_) {
      return 'Chưa nhận được kết quả thêm hàng. Bạn kiểm tra giỏ trước khi gửi lại yêu cầu nhé.';
    }
  }

  Future<String> _startCheckout() async {
    final userId = DBService.currentUserId();
    if (userId == null) return 'Bạn đăng nhập tài khoản để đặt giao tận nhà nhé ạ.';
    final cart = await ApiService.fetchCart(userId);
    if (cart.isEmpty) return 'Giỏ hàng đang trống. Bạn chọn sản phẩm và thêm vào giỏ trước nhé.';
    _shippingAddress = null;
    _phone = null;
    _paymentMethod = null;
    _checkoutStep = _CheckoutStep.address;
    return 'Dạ mình sẽ hỗ trợ đặt giao tận nhà. Bạn cho mình xin địa chỉ nhận hàng chi tiết: số nhà, đường, phường/xã và tỉnh/thành phố nhé.';
  }

  Future<String> _removeCartProducts(CartRemovalRequest request) async {
    final userId = DBService.currentUserId();
    if (userId == null) return 'Bạn đăng nhập tài khoản để sửa giỏ hàng nhé.';
    _pendingProduct = null;
    _pendingQuantity = null;
    _checkoutStep = _CheckoutStep.none;
    final cart = await ApiService.fetchCart(userId);
    if (cart.isEmpty) return 'Giỏ hàng hiện đang trống.';
    String reply;
    String? removedId;
    if (request.clearAll) {
      await ApiService.saveCart(userId, {});
      reply = 'Đã xóa toàn bộ sản phẩm trong giỏ hàng.';
    } else {
      final products = await ApiService.fetchProducts();
      final names = {for (final product in products.where((p) => cart.containsKey(p.id))) product.id: product.name};
      final matches = SmartSalesCartCommand.matchProducts(request.target, names);
      if (matches.length != 1) {
        _awaitingRemovalTarget = true;
        final options = matches.isEmpty ? names.values : matches.map((id) => names[id]!);
        return '${request.target.isNotEmpty && matches.isEmpty ? 'Mình chưa thấy sản phẩm đó trong giỏ. ' : ''}Bạn muốn xóa sản phẩm nào: ${options.join(', ')}?';
      }
      final id = matches.single;
      removedId = id;
      await ApiService.removeCartItem(userId, id);
      reply = 'Đã xóa ${names[id]} khỏi giỏ hàng.';
      if (_selectedProduct?.id == id) _selectedProduct = null;
    }
    final remaining = await ApiService.fetchCart(userId);
    if (request.clearAll ? remaining.isNotEmpty : remaining.containsKey(removedId)) {
      throw ApiException('Chưa xác nhận được kết quả xóa. Bạn kiểm tra lại giỏ nhé.');
    }
    final email = DBService.currentUserEmail();
    if (email != null) await DBService.carts().put(email, remaining);
    _lastSuggestedProducts = [];
    if (request.clearAll) _selectedProduct = null;
    return '$reply\n${remaining.isEmpty ? 'Giỏ hiện đã trống.' : 'Giỏ còn ${remaining.values.fold<int>(0, (sum, count) => sum + count)} đơn vị sản phẩm.'}';
  }

  String _productDetail(Product product, {bool suggestPurchase = true}) =>
      '🛍️ ${product.name}\n'
      '• Danh mục: ${product.categoryName ?? 'Chưa có thông tin'}\n'
      '• Mô tả: ${product.description?.trim().isNotEmpty == true ? product.description : 'Chưa có thông tin mô tả'}\n'
      '• Giá: ${product.price.toStringAsFixed(0)} VNĐ/${product.unit}\n'
      '• Tồn kho: ${product.stockQuantity} ${product.unit}'
      '${suggestPurchase ? '\n\nBạn muốn lấy bao nhiêu ${product.unit} ạ?' : ''}';

  Future<String> _answerProductQuestion(Product product, String question) async {
    if (_isAmbiguousContainerQuestion(question) &&
        !RegExp(r'gam|gram|\bml\b|khối lượng|khoi luong|dung tích|dung tich|giá|gia|cân|kg', caseSensitive: false).hasMatch(question)) {
      return 'Bạn muốn hỏi giá hay dung tích/khối lượng của ${product.name} ạ?';
    }
    final productId = int.tryParse(product.id);
    if (productId == null) return _productDetail(product, suggestPurchase: false);
    try {
      return await ApiService.askGeminiAboutProduct(
        productId: productId,
        question: question,
      );
    } catch (_) {
      return _productDetail(product, suggestPurchase: false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    setState(() {
      _messages.add(_ChatMessage(true, text));
      _input.clear();
      _loading = true;
    });
    _scrollToLatest();
    try {
      final normalized = text.toLowerCase();
      String? checkoutReply;
      final cancellationReply = await _handleOrderCancellation(text);
      if (cancellationReply != null) {
        if (mounted) setState(() => _messages.add(cancellationReply));
        _scrollToLatest();
        return;
      }
      final removal = SmartSalesCartCommand.removal(text);
      final choosingRemoval = _awaitingRemovalTarget && !_confirms(normalized) &&
          !SmartSalesIntent.wantsCheckout(normalized) && !_wantsOrders(normalized) &&
          !_needsSalesAdvice(normalized) && !_isInformationRequest(normalized) && !_wantsToBuy(normalized) && !_rejectsPurchase(normalized);
      _awaitingRemovalTarget = false;
      if (removal != null || choosingRemoval) {
        _awaitingCheckoutOffer = false;
        checkoutReply = await _removeCartProducts(removal ?? CartRemovalRequest(clearAll: false, target: text));
        if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        _scrollToLatest();
        return;
      }
      if (_checkoutStep == _CheckoutStep.confirm && RegExp(r'sai rồi|sai roi|chưa đúng|chua dung|không đúng|khong dung').hasMatch(normalized)) {
        _checkoutStep = _CheckoutStep.none;
        checkoutReply = 'Mình đã dừng xác nhận đơn. Bạn muốn sửa món nào? Có thể nhắn “xóa dâu tây”, “xóa giỏ hàng” hoặc “lấy 5 dứa” để sửa số lượng.';
        if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        _scrollToLatest();
        return;
      }
      final acceptsOffer = SmartSalesIntent.acceptsCheckoutOffer(normalized, awaitingOffer: _awaitingCheckoutOffer);
      // Lời đồng ý ngắn chỉ trả lời đề nghị ngay trước đó. Đổi chủ đề thì
      // bỏ đề nghị để một "ok" ở lượt sau không khởi động đặt đơn cũ.
      _awaitingCheckoutOffer = false;
      if (acceptsOffer && _checkoutStep == _CheckoutStep.none && _pendingProduct == null) {
        checkoutReply = await _startCheckout();
        if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        _scrollToLatest();
        return;
      }
      if (_checkoutStep != _CheckoutStep.none &&
          (_isBudgetQuestion(normalized) || _isInformationRequest(normalized) || _needsSalesAdvice(normalized))) {
        // Một câu hỏi mới không được lưu nhầm thành địa chỉ/SĐT hoặc giữ
        // xác nhận đặt đơn cũ cho một lời "ok" không còn cùng ngữ cảnh.
        _checkoutStep = _CheckoutStep.none;
      }
      final isFriendlyAck = RegExp(r'cảm ơn|cam on|thanks|thank', caseSensitive: false).hasMatch(normalized) ||
          _confirms(normalized);
      if (isFriendlyAck && _checkoutStep == _CheckoutStep.none && _pendingProduct == null) {
        try {
          checkoutReply = await ApiService.askGeminiReply(text);
        } catch (_) {
          checkoutReply = 'Dạ shop cảm ơn bạn nhiều ạ! Khi cần tìm hoặc đặt sản phẩm, bạn cứ nhắn shop nhé 😊';
        }
        if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        _scrollToLatest();
        return;
      }
      if (_rejectsPurchase(normalized) || RegExp(r'^(thôi|thoi|khỏi|khoi|để sau|de sau|không lấy nữa|khong lay nua|tôi chỉ hỏi thôi|toi chi hoi thoi)[.!?]*$', caseSensitive: false).hasMatch(normalized)) {
        _pendingProduct = null;
        _pendingQuantity = null;
        _checkoutStep = _CheckoutStep.none;
        checkoutReply = 'Dạ được bạn nhé, mình đã dừng yêu cầu mua đang chờ. Giỏ hàng hiện có vẫn được giữ nguyên.';
        if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        _scrollToLatest();
        return;
      }
      if (!SmartSalesIntent.wantsCheckout(normalized) &&
          (RegExp(r'hủy đơn|huy don', caseSensitive: false).hasMatch(normalized) || _wantsOrders(normalized))) {
        _pendingProduct = null;
        _pendingQuantity = null;
        final userId = DBService.currentUserId();
        if (userId == null) {
          checkoutReply = 'Bạn đăng nhập tài khoản để xem đơn hàng nhé ạ.';
          if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        } else {
          final allOrders = await ApiService.fetchMyOrders(userId);
          // Mặc định chỉ hiện đơn còn hiệu lực. Nếu khách hỏi rõ đơn đã hủy,
          // hiển thị đúng nhóm đó để họ tra cứu lịch sử.
          final showCancelled = _wantsCancelledOrders(normalized);
          final queriedOrderId = SmartSalesOrderIntent.orderId(text);
          if (queriedOrderId != null) _selectedOrderId = queriedOrderId;
          final orders = allOrders
              .where((order) => queriedOrderId != null
                ? '${order['order_id'] ?? order['id']}' == queriedOrderId
                : showCancelled ? _isCancelledOrder(order) : !_isCancelledOrder(order))
              .toList()
            ..sort((a, b) {
              final aId = num.tryParse('${a['order_id'] ?? a['id'] ?? 0}') ?? 0;
              final bId = num.tryParse('${b['order_id'] ?? b['id'] ?? 0}') ?? 0;
              return bId.compareTo(aId);
            });
          if (orders.isEmpty) {
            checkoutReply = await _dynamicFallback(
              message: text,
              toolResult: const {'result': 'NO_ORDERS_FOUND'},
              localFallback: showCancelled
                  ? 'Mình chưa thấy đơn nào đã hủy trong tài khoản này ạ.'
                  : 'Mình vừa kiểm tra nhưng hiện chưa có đơn còn hiệu lực. Bạn muốn xem sản phẩm để đặt đơn mới không ạ?',
            );
            if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
          } else if (_asksLatestOrder(normalized)) {
            final latest = orders.first;
            final id = latest['order_id'] ?? latest['id'];
            final total = _money(latest['final_amount'] ?? latest['total_amount'] ?? latest['totalAmount']);
            checkoutReply = 'Đơn mới nhất của bạn là đơn #$id, tổng $total và hiện ${_orderStatusLabel(latest)} ạ.';
            if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
          } else {
            final heading = showCancelled
                ? '📦 Bạn có ${orders.length} đơn đã hủy/từ chối. Nhấn vào từng đơn để xem chi tiết.'
                : RegExp(r'hủy đơn|huy don', caseSensitive: false).hasMatch(normalized)
                ? '📦 Bạn chọn đơn muốn hủy. Nhấn vào đơn để mở chi tiết và thực hiện hủy nếu đơn còn đủ điều kiện.'
                : '📦 Bạn có ${orders.length} đơn còn hiệu lực. Nhấn vào từng đơn để xem chi tiết.';
            if (mounted) setState(() => _messages.add(_ChatMessage(false, heading, orders: orders)));
          }
        }
        _scrollToLatest();
        return;
      }
      if (RegExp(r'hủy.*giỏ|bỏ.*giỏ|xem giỏ|sản phẩm.*giỏ', caseSensitive: false).hasMatch(normalized)) {
        _pendingProduct = null;
        _pendingQuantity = null;
        final userId = DBService.currentUserId();
        if (userId == null) {
          checkoutReply = 'Bạn đăng nhập tài khoản để xem giỏ hàng nhé ạ.';
        } else {
          final cart = await ApiService.fetchCart(userId);
          if (cart.isEmpty) {
            checkoutReply = await _dynamicFallback(
              message: text,
              toolResult: const {'result': 'EMPTY_CART'},
              localFallback: 'Giỏ hàng hiện đang trống nè. Bạn muốn mình tìm giúp một món phù hợp không ạ?',
            );
          } else {
            final products = await ApiService.fetchProducts();
            double cartTotal = 0;
            final lines = cart.entries.map((entry) {
              final matches = products.where((item) => item.id == entry.key);
              final product = matches.isEmpty ? null : matches.first;
              if (product != null) cartTotal += product.price * entry.value;
              return '• ${product?.name ?? 'Sản phẩm #${entry.key}'} × ${entry.value}${product == null ? '' : ' ${product.unit} — ${_money(product.price * entry.value)}'}';
            }).join('\n');
            final isRemoving = RegExp(r'hủy|huy|bỏ|bo|xóa|xoa', caseSensitive: false).hasMatch(normalized);
            checkoutReply = '🛒 Sản phẩm hiện có trong giỏ:\n$lines\nTổng tiền hàng theo giá hiện tại: ${_money(cartTotal)}${isRemoving ? '\nBạn muốn bỏ sản phẩm nào ạ?' : ''}';
          }
        }
        if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        _scrollToLatest();
        return;
      }
      // Câu hỏi ngân sách là ý định mới, không phải xác nhận số lượng cũ.
      if (_pendingProduct != null && _pendingQuantity != null && _isBudgetQuestion(normalized)) {
        _pendingProduct = null;
        _pendingQuantity = null;
      }
      if (_pendingProduct != null && _needsSalesAdvice(normalized)) {
        _selectedProduct = _pendingProduct;
        _pendingProduct = null;
        _pendingQuantity = null;
      }
      if (_pendingProduct != null && _pendingQuantity != null) {
        final pending = _pendingProduct!;
        final askedUnit = _requestedUnit(normalized);
        final unitMatches = askedUnit == null || askedUnit == _canonicalUnit(pending.unit);
        if (_abandonsPendingPurchase(normalized)) {
          _pendingProduct = null;
          _pendingQuantity = null;
          checkoutReply = 'Dạ được ạ, mình đã dừng yêu cầu thêm ${pending.name}. Khi cần tư vấn thêm bạn cứ nhắn mình nhé.';
        } else if (_isInformationRequest(normalized)) {
          // Khách đổi sang hỏi thông tin: ưu tiên trả lời, không ép xác nhận mua.
          _selectedProduct = pending;
          _pendingProduct = null;
          _pendingQuantity = null;
          checkoutReply = await _answerProductQuestion(pending, text);
        } else if (_confirms(normalized) && unitMatches) {
          checkoutReply = await _addPendingProduct(text);
        } else if (askedUnit != null && !unitMatches) {
          _pendingProduct = null;
          _pendingQuantity = null;
          checkoutReply = 'Hệ thống bán ${pending.name} theo ${pending.unit}, chưa có dữ liệu quy đổi. Bạn muốn lấy bao nhiêu ${pending.unit}?';
        } else {
          // Khách đổi ý định hoặc số lượng: bỏ xác nhận cũ và để câu mới
          // đi qua luồng xử lý bình thường, không ép xác nhận lại.
          _selectedProduct = pending;
          _pendingProduct = null;
          _pendingQuantity = null;
        }
        if (checkoutReply != null) {
          if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
          _scrollToLatest();
          return;
        }
      }
      if (_checkoutStep == _CheckoutStep.address) {
        _shippingAddress = text;
        _checkoutStep = _CheckoutStep.phone;
        checkoutReply = 'Dạ shop đã nhận địa chỉ giao hàng. Bạn cho shop xin số điện thoại người nhận nhé ạ.';
      } else if (_checkoutStep == _CheckoutStep.phone) {
        final phone = text.replaceAll(RegExp(r'[^0-9+]'), '');
        if (!RegExp(r'^0\d{9,10}$').hasMatch(phone)) {
          checkoutReply = 'Số điện thoại chưa đúng định dạng. Bạn nhập số Việt Nam gồm 10–11 chữ số giúp shop nhé.';
        } else {
          _phone = phone;
          _checkoutStep = _CheckoutStep.payment;
          checkoutReply = 'Bạn muốn thanh toán cách nào ạ?\n1. 💵 COD — thanh toán khi nhận hàng\n2. 🏦 Chuyển khoản';
        }
      } else if (_checkoutStep == _CheckoutStep.payment) {
        if (normalized.contains('cod') || normalized.contains('tiền mặt') || normalized.contains('tien mat')) {
          _paymentMethod = 'cash';
        } else if (normalized.contains('chuyển khoản') || normalized.contains('chuyen khoan') || normalized.contains('bank')) {
          _paymentMethod = 'bank_transfer';
        }
        if (_paymentMethod == null) {
          checkoutReply = 'Bạn chọn COD hoặc Chuyển khoản giúp shop nhé.';
        } else {
          final cart = await ApiService.fetchCart(DBService.currentUserId()!);
          final products = await ApiService.fetchProducts();
          double total = 0;
          final lines = <String>[];
          for (final entry in cart.entries) {
            final matched = products.where((p) => p.id == entry.key).toList();
            if (matched.isEmpty) throw ApiException('Sản phẩm trong giỏ không còn khả dụng. Bạn kiểm tra lại giỏ nhé.');
            final product = matched.first;
            total += product.price * entry.value;
            lines.add('• ${product.name}: ${entry.value} ${product.unit} × ${_money(product.price)} = ${_money(product.price * entry.value)}');
          }
          if (cart.isEmpty) {
            _checkoutStep = _CheckoutStep.none;
            checkoutReply = 'Giỏ hàng đang trống, mình chưa thể tạo đơn.';
          } else {
            _checkoutStep = _CheckoutStep.confirm;
            checkoutReply = '📦 XÁC NHẬN ĐƠN HÀNG\n${lines.join('\n')}\n• Tổng tiền hàng theo giá hiện tại: ${_money(total)}\n• Địa chỉ: $_shippingAddress\n• SĐT: $_phone\n• Thanh toán: ${_paymentMethod == 'cash' ? 'COD' : 'Chuyển khoản'}\n\nBạn đồng ý đặt đơn với thông tin trên không ạ? Nhắn “ok”, “đúng” hoặc “xác nhận” để tạo đơn.';
          }
        }
      } else if (_checkoutStep == _CheckoutStep.confirm) {
        if (_confirms(normalized)) {
          final userId = DBService.currentUserId();
          if (userId == null) {
            checkoutReply = 'Bạn đăng nhập tài khoản để hoàn tất đặt hàng nhé ạ.';
          } else {
            final order = await ApiService.checkoutOnlineOrder(
              userId: userId,
              deliveryMethod: 'delivery',
              paymentMethod: _paymentMethod!,
              shippingAddress: _shippingAddress,
              note: 'SĐT người nhận: $_phone',
            );
            _checkoutStep = _CheckoutStep.none;
            checkoutReply = '🎉 Đặt hàng thành công!\n• Mã đơn: ${order.id}\n• Tổng tiền: ${order.totalAmount.toStringAsFixed(0)} VNĐ\n• Địa chỉ: ${order.shippingAddress ?? _shippingAddress}\n• Thanh toán: ${_paymentMethod == 'cash' ? 'COD' : 'Chuyển khoản'}\n\nBạn xem lại tại tab Đơn hàng nhé.';
          }
        } else if (RegExp(r'\bhủy\b|\bhuy\b|không đặt|khong dat', caseSensitive: false).hasMatch(normalized)) {
          _checkoutStep = _CheckoutStep.none;
          _shippingAddress = null;
          _phone = null;
          _paymentMethod = null;
          checkoutReply = 'Dạ shop đã dừng tạo đơn này. Giỏ hàng của bạn vẫn được giữ lại để đặt sau nhé.';
        } else {
          checkoutReply = 'Nếu đồng ý tạo đơn, bạn chỉ cần nhắn “ok”, “được rồi”, “đúng” hoặc “xác nhận” nhé. Bạn cũng có thể nhắn “hủy” để quay lại mua sắm.';
        }
      }
      if (checkoutReply != null) {
        if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        _scrollToLatest();
        return;
      }
      if (SmartSalesIntent.wantsCheckout(normalized)) {
        checkoutReply = await _startCheckout();
        if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        _scrollToLatest();
        return;
      }
      if (_selectedProduct != null &&
          _referencesCurrentProduct(normalized) &&
          _isInformationRequest(normalized)) {
        checkoutReply = await _answerProductQuestion(_selectedProduct!, text);
        if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        _scrollToLatest();
        return;
      }
      if (_needsSalesAdvice(normalized) && !_isBudgetQuestion(normalized)) {
        try {
          final contextProducts = _lastSuggestedProducts.isNotEmpty
              ? _lastSuggestedProducts
              : (_selectedProduct == null ? <Product>[] : [_selectedProduct!]);
          checkoutReply = await ApiService.askGeminiSalesAdvice(
            text,
            candidateProductIds: contextProducts.map((product) => product.id).toList(),
          );
        } on ApiException catch (error) {
          checkoutReply = error.message;
        } catch (_) {
          checkoutReply = 'Dạ đây là câu hỏi tư vấn khá cụ thể. Hiện shop chưa thể tạo gợi ý tự động, bạn cho mình biết rõ món hoặc sản phẩm muốn kết hợp nhé.';
        }
        if (mounted) setState(() => _messages.add(_ChatMessage(false, checkoutReply!)));
        _scrollToLatest();
        return;
      }
      final products = await ApiService.fetchProducts();
      final matches = _searchProducts(products, text);
      if (matches.isNotEmpty) _lastSuggestedProducts = matches;
      final product = matches.isNotEmpty ? matches.first : _selectedProduct;
      String reply;
      final requestedQuantity = _quantity(text);
      final requestedUnit = _requestedUnit(text);
      if (_isBudgetQuestion(normalized)) {
        if (matches.isEmpty) {
          reply = 'Mình chưa thấy sản phẩm phù hợp ngân sách này trong danh sách hiện có.';
        } else {
          try {
            reply = await ApiService.askGeminiSalesAdvice(text, candidateProductIds: matches.map((p) => p.id).toList(), maxPrice: _maxPrice(text));
          } catch (_) {
            reply = 'Các lựa chọn trong ngân sách ${_money(_maxPrice(text))}:\n${matches.map((p) => '• ${p.name}: ${_money(p.price)}/${p.unit} — phù hợp vì giá không vượt ngân sách và đang còn hàng.').join('\n')}';
          }
        }
      } else if (product != null && _isInformationRequest(normalized)) {
        if (matches.length > 1) {
          reply = 'Bạn muốn xem thông tin sản phẩm nào: ${matches.map((p) => p.name).join(', ')}?';
        } else {
          _selectedProduct = product;
          reply = await _answerProductQuestion(product, text);
        }
      } else if (product != null && requestedQuantity != null &&
          (_wantsToBuy(text) || RegExp(r'^\d+(?:$|\s|kg|cân|can|hộp|hop|chai|gói|goi)', caseSensitive: false).hasMatch(text))) {
        if (matches.length > 1) {
          _pendingProduct = null;
          _pendingQuantity = null;
          reply = 'Bạn muốn chọn sản phẩm nào: ${matches.map((p) => p.name).join(', ')}?';
        } else if (requestedUnit != null && requestedUnit != _canonicalUnit(product.unit)) {
          _pendingProduct = null;
          _pendingQuantity = null;
          reply = 'Bạn đang yêu cầu $requestedQuantity $requestedUnit ${product.name}, nhưng hệ thống bán theo ${product.unit} và chưa có dữ liệu quy đổi. Bạn muốn lấy bao nhiêu ${product.unit}?';
        } else if (requestedQuantity <= 0 || requestedQuantity > product.stockQuantity) {
          reply = 'Số lượng chưa phù hợp; ${product.name} hiện còn ${product.stockQuantity} ${product.unit}.';
        } else {
          _selectedProduct = product;
          _pendingProduct = product;
          _pendingQuantity = requestedQuantity;
          _pendingCartMode = SmartSalesCartCommand.wantsIncrement(text) ? 'add' : 'set';
          reply = 'Bạn muốn ${_pendingCartMode == 'add' ? 'thêm' : 'lấy'} $requestedQuantity ${product.unit} ${product.name}${_pendingCartMode == 'set' ? ' (tổng số lượng trong giỏ là $requestedQuantity)' : ''} đúng không ạ?';
        }
      } else if (_wantsToBuy(text) && product != null) {
        if (matches.length > 1) {
          reply = 'Bạn muốn chọn sản phẩm nào: ${matches.map((p) => p.name).join(', ')}?';
        } else {
          _selectedProduct = product;
          reply = 'Bạn muốn đặt ${product.name} đúng không ạ? Bạn lấy bao nhiêu ${product.unit}?';
        }
      } else if (matches.isEmpty) {
        final isSmallTalk = _isSmallTalk(text);
        reply = await _dynamicFallback(
          message: text,
          toolResult: {
            'result': isSmallTalk ? 'OUT_OF_SCOPE' : 'NO_PRODUCTS_FOUND',
            'suggestedCategories': _suggestedCategories(products),
          },
          localFallback: isSmallTalk
              ? 'Haha, mình luôn sẵn lòng trò chuyện cùng bạn 😊 Hôm nay bạn muốn tìm món gì để giao tận nhà nè?'
              : 'Dạ mình chưa thấy mặt hàng này trong danh sách. Bạn muốn thử mô tả thêm hoặc xem một danh mục khác không ạ?',
        );
      } else if (_wantsIntroduction(text)) {
        _selectedProduct = matches.first;
        try {
          reply = await ApiService.askGeminiAboutProduct(
            productId: int.parse(matches.first.id),
            question: text,
          );
        } catch (_) {
          // Gemini có thể tạm quá tải; thông tin CSDL vẫn được hiển thị chính xác.
          reply = _productDetail(matches.first);
        }
      } else {
        _selectedProduct = matches.first;
        try {
          // Dù chỉ là tìm hàng, Gemini vẫn nhận đúng các sản phẩm đã khớp
          // từ CSDL để diễn đạt theo ngữ cảnh thay vì lắp câu mẫu cố định.
          reply = await ApiService.askGeminiSalesAdvice(
            text,
            candidateProductIds: matches.map((product) => product.id).toList(),
          );
        } catch (_) {
          // Gemini tạm quá tải: vẫn hiện dữ liệu thật để khách tiếp tục mua.
          reply = 'Mình thấy ${matches.map((p) => '${p.name} (${p.price.toStringAsFixed(0)} VNĐ, còn ${p.stockQuantity} ${p.unit})').join(', ')}. Bạn quan tâm sản phẩm nào để mình hỗ trợ tiếp ạ?';
        }
      }
      if (mounted) setState(() => _messages.add(_ChatMessage(false, reply)));
      _scrollToLatest();
    } on ApiException catch (error) {
      if (mounted) setState(() => _messages.add(_ChatMessage(false, error.message)));
      _scrollToLatest();
    } catch (error, stackTrace) {
      debugPrint('SmartSales request error (${error.runtimeType}): $error\n$stackTrace');
      if (mounted) setState(() => _messages.add(_ChatMessage(false, ApiService.requestErrorMessage(error))));
      _scrollToLatest();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .68,
      minChildSize: .42,
      maxChildSize: .92,
      builder: (context, controller) => Material(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Column(children: [
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE0F5EE), child: Icon(Icons.smart_toy_rounded, color: Color(0xFF008563))),
            title: const Text('SmartSales Assistant', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Trợ lý đặt hàng tận nhà'),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ),
          const Divider(height: 1),
          Expanded(child: ListView.builder(
            // DraggableScrollableSheet cung cấp controller để vừa kéo khung vừa tự cuộn tin nhắn.
            controller: _scrollController = controller,
            padding: const EdgeInsets.all(14),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return Align(
                alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: message.isUser ? const Color(0xFF008563) : const Color(0xFFF0F3F2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(message.text, style: TextStyle(color: message.isUser ? Colors.white : Colors.black87)),
                    if (message.orders != null) ...[
                      const SizedBox(height: 8),
                      for (final order in message.orders!)
                        Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: () => _showOrderDetail(order),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text('Đơn #${order['order_id'] ?? order['id']}\n${_money(order['final_amount'] ?? order['total_amount'] ?? order['totalAmount'])} • ${_orderStatusLabel(order)}'),
                            ),
                          ),
                        ),
                    ],
                  ]),
                ),
              );
            },
          )),
          SafeArea(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _input,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Nhập câu hỏi của bạn...', border: OutlineInputBorder()),
              )),
              IconButton(onPressed: _send, icon: _loading ? const CircularProgressIndicator() : const Icon(Icons.send, color: Color(0xFF008563))),
            ]),
          )),
        ]),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage(this.isUser, this.text, {this.orders});
  final bool isUser;
  final String text;
  final List<Map<String, dynamic>>? orders;
}

enum _CheckoutStep { none, address, phone, payment, confirm }
enum _OrderCancelStep { none, scope, reason, confirm }
