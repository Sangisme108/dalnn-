import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../widgets/slide_page_route.dart';
import 'orders_screen.dart';

class VnpayPaymentScreen extends StatefulWidget {
  final int orderId;
  final int userId;
  final double amount;

  const VnpayPaymentScreen({
    super.key,
    required this.orderId,
    required this.userId,
    required this.amount,
  });

  @override
  State<VnpayPaymentScreen> createState() => _VnpayPaymentScreenState();
}

class _VnpayPaymentScreenState extends State<VnpayPaymentScreen>
    with WidgetsBindingObserver {
  static const Color _primary = Color(0xFF1B7F4D);

  bool _isLoading = true;
  bool _isChecking = false;
  bool _openedGateway = false;
  String? _paymentUrl;
  String? _errorMessage;
  String _statusMessage = 'Đang tạo liên kết thanh toán VNPay...';
  /// null = để VNPay hiện danh sách; VNPAYQR = QR; VNBANK = thẻ nội địa
  String? _bankCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createPayment(bankCode: _bankCode);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedGateway) {
      _checkPaymentStatus(showSnackBar: true);
    }
  }

  Future<void> _createPayment({String? bankCode}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _bankCode = bankCode;
      _statusMessage = 'Đang tạo liên kết thanh toán VNPay...';
    });
    try {
      final data = await ApiService.createVnpayPayment(
        userId: widget.userId,
        orderId: widget.orderId,
        bankCode: bankCode,
      );
      final paymentUrl = data['paymentUrl']?.toString();
      if (paymentUrl == null || paymentUrl.isEmpty) {
        throw ApiException('Backend không trả về paymentUrl');
      }
      if (!mounted) return;
      setState(() {
        _paymentUrl = paymentUrl;
        _isLoading = false;
        _statusMessage =
            'Chọn cách thanh toán bên dưới rồi mở cổng VNPay sandbox.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is ApiException ? e.message : e.toString();
        _statusMessage = 'Không tạo được liên kết thanh toán.';
      });
    }
  }

  Future<void> _openPaymentGateway() async {
    final url = _paymentUrl;
    if (url == null) return;
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được cổng thanh toán VNPay')),
      );
      return;
    }
    setState(() {
      _openedGateway = true;
      _statusMessage =
          'Hoàn tất thanh toán trên VNPay, sau đó quay lại app và bấm "Kiểm tra trạng thái".';
    });
  }

  Future<void> _checkPaymentStatus({bool showSnackBar = false}) async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      final data = await ApiService.fetchOrderPaymentStatus(
        userId: widget.userId,
        orderId: widget.orderId,
      );
      final paymentStatus =
          (data['paymentStatus'] ?? data['payment_status'] ?? 'pending')
              .toString()
              .toLowerCase();
      if (!mounted) return;

      if (paymentStatus == 'paid' || paymentStatus == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanh toán thành công')),
        );
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(const OrdersScreen()),
        );
        return;
      }

      if (paymentStatus == 'failed') {
        setState(() {
          _statusMessage = 'Thanh toán thất bại. Bạn có thể thử lại hoặc chọn phương thức khác.';
          _errorMessage = null;
        });
        if (showSnackBar) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thanh toán thất bại')),
          );
        }
        return;
      }

      setState(() {
        _statusMessage = 'Đang chờ xác nhận thanh toán từ VNPay...';
      });
      if (showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang chờ xác nhận thanh toán')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Widget _sandboxGuideCard() {
    return Card(
      color: const Color(0xFFFFF8E7),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Text(
                  'Lưu ý môi trường VNPay sandbox',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Sandbox thường KHÔNG hiện mã QR thật. Chọn ngân hàng xong có thể '
              'nhảy thẳng "Thanh toán thành công" — đó là hành vi test của VNPay, '
              'không phải lỗi app.\n\n'
              'Muốn thử nhập thẻ: bấm "Thử thẻ ATM", trên VNPay chọn NCB, nhập:\n'
              '• Số thẻ: 9704198526191432198\n'
              '• OTP: 123456\n\n'
              'Muốn thử QR: bấm "Thử thanh toán QR" (sandbox có thể vẫn không hiện QR).\n'
              'Sau khi xong trên trình duyệt, quay lại app và bấm "Kiểm tra trạng thái".',
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrency(double amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} VND';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('Thanh toán VNPay'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đơn hàng #${widget.orderId}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Số tiền: ${_formatCurrency(widget.amount)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _statusMessage,
                      style: TextStyle(color: Colors.grey.shade800),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _sandboxGuideCard(),
            const SizedBox(height: 16),
            if (_isLoading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Expanded(
                child: Center(
                  child: Icon(
                    Icons.account_balance_outlined,
                    size: 88,
                    color: _primary.withValues(alpha: 0.85),
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _paymentUrl == null
                      ? null
                      : () => _openPaymentGateway(),
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Mở VNPay (chọn ngân hàng)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () => _createPayment(bankCode: 'VNPAYQR'),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Thử thanh toán QR (VNPAYQR)'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () => _createPayment(bankCode: 'VNBANK'),
                  icon: const Icon(Icons.credit_card),
                  label: const Text('Thử thẻ ATM (NCB test)'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _isChecking ? null : () => _checkPaymentStatus(),
                  icon: _isChecking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Kiểm tra trạng thái'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
