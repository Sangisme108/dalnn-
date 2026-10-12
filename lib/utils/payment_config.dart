class PaymentConfig {
  static const String bankBin = '970422';
  static const String bankName = 'MB Bank';
  static const String accountNumber = '0363489746';
  static const String accountName = 'NGUYEN VAN SANG';
  static const String template = 'compact2';
  static const String transferPrefix = 'DH';

  static String transferContent(String orderCode) {
    final normalized = orderCode.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (normalized.toUpperCase().startsWith(transferPrefix)) {
      return normalized.toUpperCase();
    }
    return '$transferPrefix$normalized';
  }

  static int amountInVnd(double amount) => amount.round();

  static Uri vietQrUri({required String orderCode, required double amount}) {
    final roundedAmount = amount.round();
    final content = transferContent(orderCode);
    return Uri.https(
      'img.vietqr.io',
      '/image/$bankBin-$accountNumber-$template.png',
      {
        'amount': roundedAmount.toString(),
        'addInfo': content,
        'accountName': accountName,
      },
    );
  }

  static String qrContent({required String orderCode, required double amount}) {
    return vietQrUri(orderCode: orderCode, amount: amount).toString();
  }
}
