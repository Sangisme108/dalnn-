/// Những ý định giao dịch rõ ràng cần hoạt động cả khi AI hết hạn mức.
class SmartSalesIntent {
  static bool isPolicyQuestion(String message) => RegExp(
    r'chính sách|chinh sach|phí ship|phi ship|phí giao|phi giao|đổi trả|doi tra|giao.*bao lâu|giao.*bao lau|có.*giao|co.*giao|có.*ship|co.*ship|thanh toán.*(?:gì|gi|nào|nao|không|khong)|(?:có|co).*cod|giờ mở cửa|gio mo cua',
    caseSensitive: false,
  ).hasMatch(message);

  static bool needsAdvice(String message) => isPolicyQuestion(message) || RegExp(
    r'sốt|sauce|chấm|cham|ăn với|an voi|kết hợp|ket hop|phối|phoi|nấu|nau|chế biến|che bien|làm món|lam mon|nên dùng|nen dung|dùng.*(?:gì|gi|loại)|dung.*(?:gi|loai)|tư vấn|tu van|hàng mới|hang moi|sản phẩm.*mới|san pham.*moi|loại nào|loai nao|cái nào|cai nao|ngon hơn|ngon hon|rẻ hơn|re hon|tiết kiệm|tiet kiem|so sánh|so sanh|khác nhau|khac nhau|mua.*(?:kèm|kem)|nên mua|nen mua|khuyến mãi|khuyen mai|giảm giá|giam gia|ưu đãi|uu dai|voucher|mã giảm|ma giam',
    caseSensitive: false,
  ).hasMatch(message);

  static bool wantsPurchase(String message) {
    final text = message.trim().toLowerCase();
    if (needsAdvice(text)) return false;
    if (RegExp(r'(?:^|\s)(?:không|khong|ko|k|khỏi|khoi)\s+(?:(?:tôi|toi|mk|mình|minh)\s+)?(?:mua|lấy|lay|đặt|dat)|chỉ hỏi|chi hoi|mua.*(?:được gì|duoc gi|đc gì|dc gi)', caseSensitive: false).hasMatch(text)) return false;
    if (RegExp(r'cho\s+(?:(?:tôi|toi|mk|mình|minh|em|anh|chị|chi|tớ|to)\s+)?(?:xem|biết|biet|hỏi|hoi|tư vấn|tu van)', caseSensitive: false).hasMatch(text)) return false;
    // Không dùng \b với động từ có dấu: nó coi chữ đ/ấ/ặ là ngoài từ.
    return RegExp(
      r'(?:^|\s)(?:lấy|lay|mua|thêm|them|đặt|dat)(?:\s|$)|(?:^|\s)cho\s+(?:(?:tôi|toi|mk|mình|minh|em|anh|chị|chi|tớ|to)\s+|\d)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static bool wantsCheckout(String message) {
    final text = message.trim().toLowerCase();
    if (RegExp(r'bao nhiêu|bao nhieu|bao lâu|bao lau|(?:^|\s)(?:phí|phi|giá|gia)(?:\s|$)', caseSensitive: false).hasMatch(text)) return false;
    if (RegExp(r'xem|hủy|huy|tra cứu|tra cuu|chi tiết|chi tiet|không|khong|\bko\b|\bk\b', caseSensitive: false).hasMatch(text)) return false;
    if (RegExp(r'^(?:tận|tan)\s+(?:nhà|nha)(?:\s+(?:ạ|a|nhé|nhe|đi|di))?[.!?]*$', caseSensitive: false).hasMatch(text)) return true;
    final deliveryDestination = RegExp(r'(?:tận|tan|về|ve|tới|toi|đến|den)\s+(?:nhà|nha)', caseSensitive: false).hasMatch(text);
    final deliveryVerb = RegExp(r'(?:^|\s)(?:đặt|dat|giao|ship)(?:\s|$)', caseSensitive: false).hasMatch(text);
    final personalRequest = RegExp(r'^(?:đặt|dat|giao|ship)\s|(?:cho|giúp|giup)\s+(?:tôi|toi|mk|mình|minh)|(?:tôi|toi|mk|mình|minh)\s+(?:muốn|muon)', caseSensitive: false).hasMatch(text);
    if (deliveryDestination && deliveryVerb && personalRequest &&
        !RegExp(r'bao nhiêu|bao nhieu|bao lâu|bao lau|phí|phi|được không|duoc khong', caseSensitive: false).hasMatch(text)) {
      return true;
    }
    if (isPolicyQuestion(text)) return false;
    return RegExp(
      r'(?:đặt|dat)\s+(?:hàng|hang|đơn|don)|(?:mua|đặt|dat|chốt|chot)\s+(?:luôn|luon)|chốt\s+đơn|chot\s+don|giao\s+tận\s+nhà|giao\s+tan\s+nha|giao\s+hàng|giao\s+hang|đặt\s+giao|dat\s+giao|thanh\s+toán|thanh\s+toan|checkout',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static bool acceptsCheckoutOffer(String message, {required bool awaitingOffer}) {
    if (!awaitingOffer) return false;
    if (wantsCheckout(message)) return true;
    final text = message.trim().toLowerCase().replaceAll(RegExp(r'[.!?,]'), '')
      .replaceFirst(RegExp(r'^(dạ|da)\s+'), '')
      .replaceFirst(RegExp(r'\s+(ạ|a|nha|nhé|nhe|shop)$'), '').trim();
    if (const {'có', 'co', 'ok', 'oke', 'okay', 'đúng', 'đúng rồi', 'dung', 'dung roi', 'ừ', 'u', 'được', 'được rồi', 'duoc', 'duoc roi', 'đồng ý', 'dong y', 'xác nhận', 'xac nhan'}.contains(text)) return true;
    // Trong ngữ cảnh vừa mời đặt giao tận nhà, lời đồng ý có thể kèm câu
    // yêu cầu dài hoặc lỗi gõ. Không cần khách lặp đúng câu mẫu.
    final affirmativeStart = RegExp(r'^(?:có|co|ok|đồng ý|dong y|được|duoc)\s', caseSensitive: false).hasMatch(text);
    final orderVerb = RegExp(r'(?:^|\s)(?:đặt|dat|giao|ship|mua|chốt|chot)(?:\s|$)', caseSensitive: false).hasMatch(text);
    final changedIntent = RegExp(r'\d|không|khong|\bko\b|\bk\b|bao nhiêu|bao nhieu|bao lâu|bao lau|phí|phi|(?:^|\s)(?:giá|gia|gì|gi|nào|nao)(?:\s|$)|xem|thêm|them|hủy|huy', caseSensitive: false).hasMatch(text);
    return affirmativeStart && orderVerb && !changedIntent;
  }
}
