import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../utils/payment_config.dart';

class BankTransferQrResult {
  final bool confirmed;
  final bool paidAutomatically;

  const BankTransferQrResult({
    required this.confirmed,
    this.paidAutomatically = false,
  });
}

class BankTransferQrScreen extends StatefulWidget {
  final String orderCode;
  final double amount;
  final String qrContent;
  final String transferContent;
  final int userId;

  const BankTransferQrScreen({
    super.key,
    required this.orderCode,
    required this.amount,
    required this.qrContent,
    required this.transferContent,
    required this.userId,
  });

  @override
  State<BankTransferQrScreen> createState() => _BankTransferQrScreenState();
}

class _BankTransferQrScreenState extends State<BankTransferQrScreen> {
  static const Duration _pollInterval = Duration(seconds: 3);
  static const Duration _pollTimeout = Duration(minutes: 10);

  Timer? _pollTimer;
  late final DateTime _startedAt;
  bool _checking = false;
  bool _timedOut = false;

  String get transferContent => widget.transferContent;
  String get vietQrUrl => widget.qrContent;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _checkPaymentStatus();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkPaymentStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String _formatCurrency(double value) {
    return '${value.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (match) => '${match[1]},')} VND';
  }

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Đã copy $label')));
  }

  Future<void> _checkPaymentStatus({bool showWaitingMessage = false}) async {
    if (_checking) return;

    final elapsed = DateTime.now().difference(_startedAt);
    if (!showWaitingMessage && elapsed >= _pollTimeout) {
      _pollTimer?.cancel();
      if (!mounted) return;
      setState(() => _timedOut = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đang chờ xác nhận thanh toán')),
      );
      return;
    }

    setState(() {
      _checking = true;
      if (showWaitingMessage) _timedOut = false;
    });
    try {
      final data = await ApiService.fetchOrderPaymentStatusByCode(
        transferContent,
      );
      final status = (data['paymentStatus'] ?? '').toString().toLowerCase();
      if (status == 'paid' || status == 'success') {
        _pollTimer?.cancel();
        if (!mounted) return;
        Navigator.pop(
          context,
          const BankTransferQrResult(confirmed: true, paidAutomatically: true),
        );
        return;
      }

      if (showWaitingMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa nhận được xác nhận thanh toán')),
        );
      }
    } catch (_) {
      if (showWaitingMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa kiểm tra được trạng thái thanh toán'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _confirmTransfer(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận thủ công?'),
        content: Text(
          'Chỉ dùng khi demo hoặc khi đã kiểm tra khách chuyển đúng ${_formatCurrency(widget.amount)} với nội dung "$transferContent".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kiểm tra lại'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận đã chuyển'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      Navigator.pop(context, const BankTransferQrResult(confirmed: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('Thanh toán QR'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _formatCurrency(widget.amount),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1B7F4D),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Quét VietQR hoặc nhập thông tin chuyển khoản bên dưới',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  _statusNotice(),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Image.network(
                        vietQrUrl,
                        width: 260,
                        height: 260,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const SizedBox(
                            width: 260,
                            height: 260,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return SizedBox(
                            width: 260,
                            height: 260,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.qr_code_2,
                                  size: 54,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(height: 10),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'Không tải được mã QR, vui lòng kiểm tra mạng',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _infoTile('Ngân hàng', PaymentConfig.bankName),
                  _infoTile('Mã BIN VietQR', PaymentConfig.bankBin),
                  _copyTile(
                    context,
                    'Số tài khoản',
                    PaymentConfig.accountNumber,
                  ),
                  _infoTile('Chủ tài khoản', PaymentConfig.accountName),
                  _infoTile('Số tiền', _formatCurrency(widget.amount)),
                  _copyTile(context, 'Nội dung', transferContent),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: _checking
                        ? null
                        : () => _checkPaymentStatus(showWaitingMessage: true),
                    icon: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Kiểm tra lại thanh toán'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _confirmTransfer(context),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Tôi đã chuyển khoản (thủ công)'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1B7F4D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const BankTransferQrResult(confirmed: false),
                    ),
                    child: const Text('Hủy / quay lại'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusNotice() {
    final color = _timedOut ? Colors.orange.shade700 : Colors.blue.shade700;
    final bg = _timedOut ? Colors.orange.shade50 : Colors.blue.shade50;
    final text = _timedOut
        ? 'Quá thời gian tự kiểm tra. Bấm kiểm tra lại hoặc xác nhận thủ công sau khi đối soát.'
        : 'Đang chờ webhook biến động số dư từ Casso/SePay. Khi backend nhận tiền vào, đơn sẽ tự chuyển thành đã thanh toán.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_timedOut ? Icons.schedule : Icons.sync, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _copyTile(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: _infoTile(label, value)),
          IconButton(
            onPressed: () => _copy(context, label.toLowerCase(), value),
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Copy $label',
          ),
        ],
      ),
    );
  }
}
