class CartRemovalRequest {
  const CartRemovalRequest({required this.clearAll, required this.target});
  final bool clearAll;
  final String target;
}

class SmartSalesCartCommand {
  static String normalize(String value) {
    var result = value.toLowerCase();
    const groups = {
      'a': 'àáảãạăằắẳẵặâầấẩẫậ', 'e': 'èéẻẽẹêềếểễệ',
      'i': 'ìíỉĩị', 'o': 'òóỏõọôồốổỗộơờớởỡợ',
      'u': 'ùúủũụưừứửữự', 'y': 'ỳýỷỹỵ', 'd': 'đ',
    };
    for (final entry in groups.entries) {
      result = result.replaceAll(RegExp('[${entry.value}]'), entry.key);
    }
    return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static CartRemovalRequest? removal(String message) {
    final text = normalize(message);
    if (RegExp(r'\b(dung|khong|ko|k|chua)\s+(xoa|bo|huy)\b|\b(huy|xoa)\s+don\b').hasMatch(text)) return null;
    final verb = RegExp(r'\b(xoa|bo|remove|huy)\b').firstMatch(text);
    if (verb == null || (verb.group(1) == 'huy' && !text.contains('gio'))) return null;
    final rest = text.substring(verb.end).trim();
    final genericProduct = RegExp(r'\b(san pham|sp|mon)\b').hasMatch(rest);
    final raw = message.toLowerCase();
    final rawVerb = RegExp(r'(?:^|\s)(xóa|xoá|xoa|bỏ|bo|remove|hủy|huy)(?:\s|$)').firstMatch(raw);
    var target = (rawVerb == null ? rest : raw.substring(rawVerb.end))
      .replaceAll(RegExp(r'(?:ra khỏi|ra khoi|trong|khỏi|khoi|vào|vao)\s+(?:giỏ|gio)(?:\s+(?:hàng|hang))?|(?:giỏ|gio)(?:\s+(?:hàng|hang))?'), ' ')
      .replaceAll(RegExp(r'(?:cho|giúp|giup)\s+(?:tôi|toi|mình|minh|mk|em|anh|chị|chi)|sản phẩm|san pham|(?:^|\s)sp(?:\s|$)'), ' ')
      .replaceAll(RegExp(r'(?:^|\s)(?:tất cả|tat ca|toàn bộ|toan bo|hết|het|ra|đi|di|ạ|a|nhé|nhe|nha)(?=\s|$)|[.!?,]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ').trim();
    final clearAll = target.isEmpty && !genericProduct &&
      RegExp(r'\bgio\b|\b(tat ca|toan bo|het)\b').hasMatch(rest);
    return CartRemovalRequest(clearAll: clearAll, target: target);
  }

  static bool wantsIncrement(String message) => RegExp(r'\bthem\b').hasMatch(normalize(message));

  static List<String> matchProducts(String target, Map<String, String> names) {
    final query = normalize(target);
    if (query.isEmpty) return [];
    if (names.containsKey(query)) return [query];
    // Giữ ưu tiên dấu tiếng Việt để phân biệt dứa và dưa hấu.
    final accented = target.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
    final exactAccent = names.entries.where((entry) =>
      entry.value.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').contains(accented)).map((entry) => entry.key).toList();
    if (exactAccent.isNotEmpty) return exactAccent;
    final words = query.split(' ');
    return names.entries.where((entry) {
      final nameWords = normalize(entry.value).split(' ');
      return words.every(nameWords.contains);
    }).map((entry) => entry.key).toList();
  }
}
