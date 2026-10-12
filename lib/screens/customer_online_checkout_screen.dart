import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/voucher.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/voucher_service.dart';
import '../utils/constants.dart';
import '../utils/payment_config.dart';
import '../utils/product_asset_resolver.dart';
import '../widgets/product_image_widget.dart';
import '../widgets/slide_page_route.dart';
import '../widgets/vietnam_address_form.dart';
import 'bank_transfer_qr_screen.dart';
import 'orders_screen.dart';
import 'vnpay_payment_screen.dart';

class CustomerOnlineCheckoutScreen extends StatefulWidget {
  final Map<String, int> cart;
  final VoidCallback onCheckoutComplete;

  const CustomerOnlineCheckoutScreen({
    super.key,
    required this.cart,
    required this.onCheckoutComplete,
  });

  @override
  State<CustomerOnlineCheckoutScreen> createState() =>
      _CustomerOnlineCheckoutScreenState();
}

class _CustomerOnlineCheckoutScreenState
    extends State<CustomerOnlineCheckoutScreen> {
  static const Color _primary = Color(0xFF1B7F4D);
  static const Color _accent = Color(0xFF2563EB);
  static const Color _surface = Color(0xFFF6F7F9);
  static const Color _card = Colors.white;
  static const Color _ink = Color(0xFF111827);

  final TextEditingController _voucherController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  late final Map<String, int> _cart;

  String _deliveryMethod = 'pickup';
  String _addressSource = 'account';
  String _accountAddress = '';
  String? _newAddress;
  DateTime? _pickupTime;
  String _paymentMethod = 'cash';
  bool _isApplyingVoucher = false;
  bool _isLoadingSavedVouchers = true;
  bool _isCheckingOut = false;
  String? _voucherCode;
  String? _voucherMessage;
  double _discountAmount = 0;
  List<Voucher> _savedVouchers = [];

  @override
  void initState() {
    super.initState();
    _cart = Map<String, int>.from(widget.cart)
      ..removeWhere((key, value) => value <= 0);
    _loadAccountAddress();
    _loadSavedVouchers();
  }

  @override
  void dispose() {
    _voucherController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Map<String, Product> _productById() {
    return {
      for (final product in DBService.getAllProducts()) product.id: product,
    };
  }

  List<MapEntry<String, int>> _visibleEntries(Map<String, Product> products) {
    return _cart.entries
        .where((entry) => entry.value > 0 && products.containsKey(entry.key))
        .toList();
  }

  double _subtotal(Map<String, Product> products) {
    double total = 0;
    for (final entry in _visibleEntries(products)) {
      total += products[entry.key]!.price * entry.value;
    }
    return total;
  }

  int _itemsCount() => _cart.values.fold(0, (sum, quantity) => sum + quantity);

  String _formatCurrency(double amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} VND';
  }

  int? _currentUserId() {
    final raw = DBService.settings().get('current_user_id');
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  void _loadAccountAddress() {
    final userId = _currentUserId();
    final email = DBService.currentUserEmail();
    for (final user in DBService.users().values) {
      if ((userId != null && user.userId == userId) ||
          (email != null && user.email == email)) {
        _accountAddress = user.address.trim();
        break;
      }
    }
    if (_accountAddress.isEmpty) _addressSource = 'new';
  }

  String? get _selectedShippingAddress {
    if (_deliveryMethod != 'delivery') return null;
    return _addressSource == 'account' ? _accountAddress : _newAddress;
  }

  String _formatPickupTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute, $day/$month/${value.year}';
  }

  Future<void> _selectPickupTime() async {
    final now = DateTime.now();
    final initial = _pickupTime ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!selected.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thời gian nhận phải ở trong tương lai')),
      );
      return;
    }
    setState(() => _pickupTime = selected);
  }

  Future<void> _loadSavedVouchers() async {
    final userId = _currentUserId();
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _savedVouchers = [];
        _isLoadingSavedVouchers = false;
      });
      return;
    }

    final token = (DBService.settings().get('auth_token') ?? '').toString();
    final vouchers = await VoucherService.getUserVouchers(userId, token);
    if (!mounted) return;
    setState(() {
      _savedVouchers = vouchers;
      _isLoadingSavedVouchers = false;
    });
  }

  void _clearVoucher() {
    _voucherCode = null;
    _discountAmount = 0;
    _voucherMessage = null;
    _voucherController.clear();
  }

  Future<void> _persistCart() async {
    final email = DBService.currentUserEmail();
    if (email != null) {
      await DBService.saveCartForUser(email, _cart);
    }
  }

  Future<void> _increaseQty(Product product) async {
    final current = _cart[product.id] ?? 0;
    if (current >= product.stockQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} đã đạt giới hạn tồn kho')),
      );
      return;
    }
    setState(() {
      _cart[product.id] = current + 1;
      _clearVoucher();
    });
    await _persistCart();
  }

  Future<void> _decreaseQty(Product product) async {
    final current = _cart[product.id] ?? 0;
    setState(() {
      if (current <= 1) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = current - 1;
      }
      _clearVoucher();
    });
    await _persistCart();
  }

  Future<void> _removeItem(Product product) async {
    setState(() {
      _cart.remove(product.id);
      _clearVoucher();
    });
    await _persistCart();
  }

  Future<void> _applyVoucher(double subtotal) async {
    final code = _voucherController.text.trim().toUpperCase();
    final userId = _currentUserId();
    if (code.isEmpty || userId == null) {
      setState(() => _voucherMessage = 'Nhập mã ưu đãi hợp lệ');
      return;
    }

    setState(() {
      _isApplyingVoucher = true;
      _voucherMessage = null;
    });
    try {
      final voucher = await ApiService.validateVoucher(
        code: code,
        orderTotal: subtotal,
        userId: userId,
      );
      final discount =
          double.tryParse(voucher['discountAmount']?.toString() ?? '0') ?? 0;
      setState(() {
        _voucherCode = code;
        _discountAmount = discount;
        _voucherMessage = 'Đã áp dụng $code';
      });
    } catch (e) {
      setState(() {
        _voucherCode = null;
        _discountAmount = 0;
        _voucherMessage = e is ApiException ? e.message : e.toString();
      });
    } finally {
      if (mounted) setState(() => _isApplyingVoucher = false);
    }
  }

  Future<void> _checkout() async {
    if (_isCheckingOut) return;
    final products = _productById();
    final payableTotal = (_subtotal(products) - _discountAmount)
        .clamp(0, double.infinity)
        .toDouble();
    if (payableTotal > AppConstants.maxPaymentAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppConstants.maxPaymentAmountMessage),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final userId = _currentUserId();
    final email = DBService.currentUserEmail();
    if (userId == null || email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy người dùng hiện tại')),
      );
      return;
    }
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Giỏ hàng đang trống')));
      return;
    }
    if (_deliveryMethod == 'pickup' && _pickupTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn thời gian nhận tại quầy')),
      );
      return;
    }
    if (_deliveryMethod == 'delivery' &&
        (_selectedShippingAddress?.trim().isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _addressSource == 'account'
                ? 'Tài khoản chưa có địa chỉ giao hàng'
                : 'Vui lòng nhập đầy đủ địa chỉ giao hàng mới',
          ),
        ),
      );
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Đặt hàng?'),
        content: const Text('Kiểm tra lại thông tin trước khi tạo đơn hàng.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Đặt hàng'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() => _isCheckingOut = true);
    try {
      final order = await ApiService.checkoutOnlineOrder(
        userId: userId,
        deliveryMethod: _deliveryMethod,
        paymentMethod: _paymentMethod,
        shippingAddress: _selectedShippingAddress,
        pickupTime: _deliveryMethod == 'pickup' ? _pickupTime : null,
        voucherCode: _voucherCode,
        note: _noteController.text,
      );
      await DBService.carts().put(email, <String, int>{});
      await DBService.orders().put(order.id, order);
      widget.onCheckoutComplete();
      DBService.syncProductsFromApi();

      if (!mounted) return;

      if (_paymentMethod == 'vnpay') {
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(
            VnpayPaymentScreen(
              orderId: int.parse(order.id),
              userId: userId,
              amount: order.totalAmount,
            ),
          ),
        );
        return;
      }

      if (_paymentMethod == 'bank_transfer') {
        final transferContent =
            order.transferContent ?? PaymentConfig.transferContent(order.id);
        final qrContent = PaymentConfig.qrContent(
          orderCode: transferContent,
          amount: order.totalAmount,
        );
        final navigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        final result = await navigator.push<BankTransferQrResult>(
          buildSlidePageRoute(
            BankTransferQrScreen(
              orderCode: order.id,
              amount: order.totalAmount,
              qrContent: qrContent,
              transferContent: transferContent,
              userId: userId,
            ),
          ),
        );

        if (!mounted) return;
        if (result?.confirmed == true) {
          if (!result!.paidAutomatically) {
            await ApiService.confirmBankTransferManual(
              userId: userId,
              orderId: int.parse(order.id),
            );
            if (!mounted) return;
          }
          messenger.showSnackBar(
            const SnackBar(content: Text('Thanh toán QR thành công')),
          );
          navigator.pushReplacement(buildSlidePageRoute(const OrdersScreen()));
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('Đơn đang chờ thanh toán QR')),
          );
          navigator.pushReplacement(buildSlidePageRoute(const OrdersScreen()));
        }
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đặt hàng thành công')));
      Navigator.of(
        context,
      ).pushReplacement(buildSlidePageRoute(const OrdersScreen()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _productById();
    final entries = _visibleEntries(products);
    final subtotal = _subtotal(products);
    final finalTotal = subtotal - _discountAmount;

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text('Giỏ hàng và thanh toán'),
        backgroundColor: _surface,
        foregroundColor: _ink,
        elevation: 0,
      ),
      body: entries.isEmpty
          ? _emptyState()
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 820;
                final content = _checkoutContent(
                  products: products,
                  entries: entries,
                  subtotal: subtotal,
                  finalTotal: finalTotal,
                  wide: wide,
                );
                if (!wide) return content;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: content,
                  ),
                );
              },
            ),
      bottomNavigationBar: entries.isEmpty
          ? null
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 820) return const SizedBox.shrink();
                return _mobileSummary(subtotal, finalTotal);
              },
            ),
    );
  }

  Widget _checkoutContent({
    required Map<String, Product> products,
    required List<MapEntry<String, int>> entries,
    required double subtotal,
    required double finalTotal,
    required bool wide,
  }) {
    final list = ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, wide ? 24 : 150),
      children: [
        _heroHeader(),
        const SizedBox(height: 14),
        _sectionCard(
          title: 'Sản phẩm trong giỏ',
          subtitle: '${_itemsCount()} sản phẩm',
          icon: Icons.shopping_bag_outlined,
          child: Column(
            children: entries
                .map((entry) => _cartItem(products[entry.key]!, entry.value))
                .toList(),
          ),
        ),
        _sectionCard(
          title: 'Mã ưu đãi',
          subtitle: 'Nhập coupon để giảm tổng đơn',
          icon: Icons.local_offer_outlined,
          child: _voucherInput(subtotal),
        ),
        _sectionCard(
          title: 'Nhận hàng',
          subtitle: _deliveryMethod == 'delivery'
              ? 'Dự kiến giao trong 24-48h'
              : _pickupTime == null
              ? 'Chọn thời gian bạn đến nhận hàng'
              : 'Nhận lúc ${_formatPickupTime(_pickupTime!)}',
          icon: Icons.local_shipping_outlined,
          child: _deliveryOptions(),
        ),
        _sectionCard(
          title: 'Thanh toán',
          subtitle: 'Chọn phương thức phù hợp',
          icon: Icons.payments_outlined,
          child: _paymentOptions(),
        ),
        _sectionCard(
          title: 'Ghi chú',
          subtitle: 'Yêu cầu đóng gói hoặc liên hệ',
          icon: Icons.notes_outlined,
          child: TextField(
            controller: _noteController,
            decoration: InputDecoration(
              hintText: 'Ví dụ: Gọi trước khi giao, cần túi riêng...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            minLines: 2,
            maxLines: 3,
          ),
        ),
      ],
    );

    if (!wide) return list;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 7, child: list),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 16, 24),
            child: _summaryPanel(subtotal, finalTotal, sticky: true),
          ),
        ),
      ],
    );
  }

  Widget _heroHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B7F4D), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(
            Icons.shopping_cart_checkout_rounded,
            color: Colors.white,
            size: 34,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hoàn tất đơn hàng',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Kiểm tra giỏ hàng, áp dụng ưu đãi và chọn cách nhận hàng.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartItem(Product product, int quantity) {
    final lineTotal = product.price * quantity;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: ProductImageWidget(
              product: product,
              assetFallback: ProductAssetResolver.forProduct,
              height: 68,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatCurrency(product.price)} / ${product.unit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _qtyButton(
                      icon: Icons.remove,
                      onPressed: () => _decreaseQty(product),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '$quantity',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    _qtyButton(
                      icon: Icons.add,
                      onPressed: () => _increaseQty(product),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _removeItem(product),
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.red.shade600,
                      tooltip: 'Xóa',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _formatCurrency(lineTotal),
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton({required IconData icon, required VoidCallback onPressed}) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton.filledTonal(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          foregroundColor: _ink,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  String _voucherDiscountText(Voucher voucher) {
    if (voucher.discountType == 'percent') {
      final max = voucher.maxDiscount == null
          ? ''
          : ' tối đa ${_formatCurrency(voucher.maxDiscount!)}';
      return 'Giảm ${voucher.discountValue.toStringAsFixed(0)}%$max';
    }
    return 'Giảm ${_formatCurrency(voucher.discountValue)}';
  }

  Widget _savedVoucherList(double subtotal) {
    if (_isLoadingSavedVouchers) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_savedVouchers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'Bạn chưa lưu voucher nào. Vào tab Ưu đãi để lấy mã.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Voucher đã lưu',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ..._savedVouchers.map(
          (voucher) => _savedVoucherTile(voucher, subtotal),
        ),
      ],
    );
  }

  Widget _savedVoucherTile(Voucher voucher, double subtotal) {
    final canUse = voucher.isValid(subtotal);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: canUse ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: canUse ? Colors.blue.shade100 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.local_offer_outlined,
            color: canUse ? _accent : Colors.black38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  voucher.code,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  voucher.minOrderAmount > subtotal
                      ? 'Cần đơn từ ${_formatCurrency(voucher.minOrderAmount)}'
                      : _voucherDiscountText(voucher),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: canUse
                ? () {
                    _voucherController.text = voucher.code;
                    _applyVoucher(subtotal);
                  }
                : null,
            child: const Text('Dùng'),
          ),
        ],
      ),
    );
  }

  Widget _voucherInput(double subtotal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _voucherController,
                enabled: _voucherCode == null,
                decoration: InputDecoration(
                  hintText: 'Nhập mã voucher',
                  prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
            const SizedBox(width: 8),
            if (_voucherCode == null)
              ElevatedButton(
                onPressed: _isApplyingVoucher
                    ? null
                    : () => _applyVoucher(subtotal),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isApplyingVoucher
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Áp dụng'),
              )
            else
              OutlinedButton(
                onPressed: () => setState(_clearVoucher),
                child: const Text('Bỏ'),
              ),
          ],
        ),
        if (_voucherMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _voucherMessage!,
            style: TextStyle(
              color: _voucherCode == null ? Colors.red : _primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        _savedVoucherList(subtotal),
      ],
    );
  }

  Widget _deliveryOptions() {
    return Column(
      children: [
        _optionTile(
          selected: _deliveryMethod == 'pickup',
          onTap: () => setState(() => _deliveryMethod = 'pickup'),
          icon: Icons.storefront_outlined,
          title: 'Nhận tại cửa hàng',
          subtitle: 'Nhận đơn tại quầy sau khi nhân viên xác nhận.',
        ),
        if (_deliveryMethod == 'pickup') ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _selectPickupTime,
            icon: const Icon(Icons.schedule_outlined),
            label: Text(
              _pickupTime == null
                  ? 'Chọn thời gian nhận tại quầy'
                  : 'Nhận lúc ${_formatPickupTime(_pickupTime!)}',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              alignment: Alignment.centerLeft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _optionTile(
          selected: _deliveryMethod == 'delivery',
          onTap: () => setState(() => _deliveryMethod = 'delivery'),
          icon: Icons.local_shipping_outlined,
          title: 'Giao tận nhà',
          subtitle: 'Dự kiến 24-48h, nhân viên sẽ liên hệ trước khi giao.',
        ),
        if (_deliveryMethod == 'delivery') ...[
          const SizedBox(height: 12),
          _addressChoice(
            value: 'account',
            title: 'Địa chỉ tài khoản',
            subtitle: _accountAddress.isEmpty
                ? 'Tài khoản chưa có địa chỉ'
                : _accountAddress,
            enabled: _accountAddress.isNotEmpty,
          ),
          const SizedBox(height: 8),
          _addressChoice(
            value: 'new',
            title: 'Nhập địa chỉ mới',
            subtitle: 'Chọn tỉnh, quận/huyện, phường/xã và số nhà',
          ),
          if (_addressSource == 'new') ...[
            const SizedBox(height: 14),
            VietnamAddressForm(
              onAddressChanged: (address) => _newAddress = address,
            ),
          ],
        ],
      ],
    );
  }

  Widget _addressChoice({
    required String value,
    required String title,
    required String subtitle,
    bool enabled = true,
  }) {
    final selected = _addressSource == value;
    return InkWell(
      onTap: enabled ? () => setState(() => _addressSource = value) : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? _primary.withValues(alpha: 0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _primary : Colors.black12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: enabled
                  ? (selected ? _primary : Colors.black45)
                  : Colors.black26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: enabled ? _ink : Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: enabled ? Colors.black54 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentOptions() {
    return Column(
      children: [
        _optionTile(
          selected: _paymentMethod == 'cash',
          onTap: () => setState(() => _paymentMethod = 'cash'),
          icon: Icons.payments_outlined,
          title: 'Tiền mặt',
          subtitle: 'Thanh toán khi nhận hàng hoặc tại quầy.',
        ),
        const SizedBox(height: 10),
        _optionTile(
          selected: _paymentMethod == 'bank_transfer',
          onTap: () => setState(() => _paymentMethod = 'bank_transfer'),
          icon: Icons.qr_code_2_outlined,
          title: 'Chuyển khoản QR',
          subtitle: 'Quét QR để thanh toán',
        ),
      ],
    );
  }

  Widget _optionTile({
    required bool selected,
    required VoidCallback onTap,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? _primary.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _primary : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? _primary : Colors.black45,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(icon, color: selected ? _primary : Colors.black54),
          ],
        ),
      ),
    );
  }

  Widget _summaryPanel(
    double subtotal,
    double finalTotal, {
    bool sticky = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tóm tắt đơn hàng',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _moneyRow('Tạm tính', subtotal),
          _moneyRow('Phí dịch vụ', 0),
          if (_discountAmount > 0) _moneyRow('Giảm giá', -_discountAmount),
          const Divider(height: 24),
          _moneyRow('Tổng thanh toán', finalTotal, isTotal: true),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 18,
                color: Colors.black54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _deliveryMethod == 'delivery'
                      ? 'Dự kiến giao: 24-48h'
                      : _pickupTime == null
                      ? 'Chưa chọn thời gian nhận tại cửa hàng'
                      : 'Nhận lúc ${_formatPickupTime(_pickupTime!)}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isCheckingOut ? null : _checkout,
              icon: _isCheckingOut
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.lock_outline),
              label: Text(_isCheckingOut ? 'Đang tạo đơn...' : 'Đặt hàng'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileSummary(double subtotal, double finalTotal) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: _summaryPanel(subtotal, finalTotal),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _moneyRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isTotal ? _ink : Colors.black54,
                fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
                fontSize: isTotal ? 17 : 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _formatCurrency(amount),
                maxLines: 1,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: isTotal ? _primary : _ink,
                  fontSize: isTotal ? 19 : 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 44,
                color: _primary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Giỏ hàng đang trống',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thêm sản phẩm vào giỏ để bắt đầu thanh toán online.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Tiếp tục mua hàng'),
            ),
          ],
        ),
      ),
    );
  }
}
