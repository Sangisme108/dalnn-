import 'package:flutter/material.dart';

import '../models/voucher.dart';
import '../services/db_service.dart';
import '../services/voucher_service.dart';
import '../widgets/role_bottom_navigation_bar.dart';
import '../widgets/slide_page_route.dart';
import 'customer_online_checkout_screen.dart';
import 'orders_screen.dart';
import 'profile_route.dart';

class CustomerVouchersScreen extends StatefulWidget {
  const CustomerVouchersScreen({super.key});

  @override
  State<CustomerVouchersScreen> createState() => _CustomerVouchersScreenState();
}

class _CustomerVouchersScreenState extends State<CustomerVouchersScreen> {
  bool _isLoading = true;
  int? _claimingVoucherId;
  String? _error;
  List<Voucher> _availableVouchers = [];
  List<Voucher> _savedVouchers = [];

  static const Color _primary = Color(0xFF2563EB);
  static const Color _surface = Color(0xFFF6F7F9);

  @override
  void initState() {
    super.initState();
    _loadVouchers();
  }

  Future<void> _loadVouchers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = DBService.currentUserId();
      final token = (DBService.settings().get('auth_token') ?? '').toString();
      final available = await VoucherService.getAvailableVouchers();
      final saved = userId == null
          ? <Voucher>[]
          : await VoucherService.getUserVouchers(userId, token);

      if (!mounted) return;
      setState(() {
        _availableVouchers = available;
        _savedVouchers = saved;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _claimVoucher(Voucher voucher) async {
    if (DBService.currentUserId() == null) {
      _showMessage('Vui lòng đăng nhập để lấy mã voucher');
      return;
    }

    setState(() => _claimingVoucherId = voucher.id);
    final token = (DBService.settings().get('auth_token') ?? '').toString();
    final result = await VoucherService.claimVoucher(
      voucherId: voucher.id,
      token: token,
    );

    if (!mounted) return;
    setState(() => _claimingVoucherId = null);

    if (result['success'] == true) {
      _showMessage('Đã lưu mã ${voucher.code} vào tài khoản');
      await _loadVouchers();
    } else {
      _showMessage(
        (result['message'] ?? 'Không thể lấy mã voucher').toString(),
      );
    }
  }

  Future<void> _openCart() async {
    final email = DBService.currentUserEmail();
    if (email == null) {
      _showMessage('Không tìm thấy người dùng hiện tại');
      return;
    }

    final cart = await DBService.loadCartForCurrentUser(email);
    if (cart.isEmpty) {
      _showMessage('Giỏ hàng đang trống');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      buildSlidePageRoute(
        CustomerOnlineCheckoutScreen(
          cart: Map<String, int>.from(cart),
          onCheckoutComplete: () async {
            await DBService.saveCartForUser(email, <String, int>{});
          },
        ),
      ),
    );
  }

  void _handleBottomTab(RoleBottomTab tab) {
    switch (tab) {
      case RoleBottomTab.home:
        Navigator.of(context).popUntil((route) => route.isFirst);
        break;
      case RoleBottomTab.offers:
        break;
      case RoleBottomTab.cart:
        _openCart();
        break;
      case RoleBottomTab.orders:
        Navigator.of(context).push(buildSlidePageRoute(const OrdersScreen()));
        break;
      case RoleBottomTab.account:
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(buildProfileScreenForRole('customer')),
        );
        break;
      case RoleBottomTab.employees:
      case RoleBottomTab.invoices:
      case RoleBottomTab.confirmOrders:
      case RoleBottomTab.scan:
        break;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Set<int> get _savedIds => _savedVouchers.map((voucher) => voucher.id).toSet();

  String _formatCurrency(double amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} VND';
  }

  String _discountText(Voucher voucher) {
    if (voucher.discountType == 'percent') {
      final max = voucher.maxDiscount == null
          ? ''
          : ' tối đa ${_formatCurrency(voucher.maxDiscount!)}';
      return 'Giảm ${voucher.discountValue.toStringAsFixed(0)}%$max';
    }
    return 'Giảm ${_formatCurrency(voucher.discountValue)}';
  }

  String _expiryText(Voucher voucher) {
    final date = voucher.expiryDate;
    if (date == null) return 'Không giới hạn hạn dùng';
    return 'HSD ${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text(
          'Voucher',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: _surface,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadVouchers,
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadVouchers,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loadVouchers,
                    child: const Text('Thử lại'),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _savedSummary(),
                  const SizedBox(height: 16),
                  const Text(
                    'Voucher đang có',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  if (_availableVouchers.isEmpty)
                    const _EmptyMessage(text: 'Chưa có voucher khả dụng')
                  else
                    ..._availableVouchers.map(_voucherCard),
                  const SizedBox(height: 18),
                  const Text(
                    'Đã lưu vào tài khoản',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  if (_savedVouchers.isEmpty)
                    const _EmptyMessage(text: 'Bạn chưa lưu voucher nào')
                  else
                    ..._savedVouchers.map(_savedVoucherTile),
                ],
              ),
      ),
      bottomNavigationBar: RoleBottomNavigationBar(
        role: 'customer',
        currentTab: RoleBottomTab.offers,
        onTabSelected: _handleBottomTab,
      ),
    );
  }

  Widget _savedSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.confirmation_number_outlined, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_savedVouchers.length} voucher đã lưu',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Text(
            'Dùng khi thanh toán',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _voucherCard(Voucher voucher) {
    final isSaved = _savedIds.contains(voucher.id);
    final isClaiming = _claimingVoucherId == voucher.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSaved
              ? const Color(0xFFBBF7D0)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.local_offer, color: _primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  voucher.code,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _discountText(voucher),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  voucher.minOrderAmount > 0
                      ? 'Đơn từ ${_formatCurrency(voucher.minOrderAmount)}'
                      : 'Không yêu cầu giá trị tối thiểu',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  _expiryText(voucher),
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                if ((voucher.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    voucher.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: ElevatedButton(
              onPressed: isSaved || isClaiming
                  ? null
                  : () => _claimVoucher(voucher),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSaved ? Colors.grey.shade200 : _primary,
                foregroundColor: isSaved ? Colors.black54 : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isClaiming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isSaved ? 'Đã lưu' : 'Lấy mã'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _savedVoucherTile(Voucher voucher) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  voucher.code,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_discountText(voucher)} • ${_expiryText(voucher)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  final String text;

  const _EmptyMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(text)),
    );
  }
}
