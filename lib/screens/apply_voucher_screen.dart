import 'package:flutter/material.dart';
import '../models/voucher.dart';
import '../services/voucher_service.dart';

class ApplyVoucherScreen extends StatefulWidget {
  final double orderTotal;
  final int userId;
  final Function(Map<String, dynamic>)? onVoucherApplied;

  const ApplyVoucherScreen({
    Key? key,
    required this.orderTotal,
    required this.userId,
    this.onVoucherApplied,
  }) : super(key: key);

  @override
  _ApplyVoucherScreenState createState() => _ApplyVoucherScreenState();
}

class _ApplyVoucherScreenState extends State<ApplyVoucherScreen> {
  final TextEditingController _codeController = TextEditingController();
  List<Voucher> availableVouchers = [];
  Voucher? selectedVoucher;
  double discountAmount = 0;
  bool isLoading = false;
  String? errorMessage;
  String? successMessage;

  @override
  void initState() {
    super.initState();
    _loadAvailableVouchers();
  }

  // Lấy danh sách vouchers khả dụng
  Future<void> _loadAvailableVouchers() async {
    setState(() => isLoading = true);
    try {
      final vouchers = await VoucherService.getAvailableVouchers();
      setState(() {
        availableVouchers = vouchers
            .where((v) => widget.orderTotal >= v.minOrderAmount)
            .toList();
      });
    } catch (e) {
      print('Lỗi: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // Validate voucher từ mã nhập
  Future<void> _validateVoucher() async {
    if (_codeController.text.isEmpty) {
      setState(() => errorMessage = 'Vui lòng nhập mã voucher');
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
      successMessage = null;
    });

    try {
      final result = await VoucherService.validateVoucher(
        code: _codeController.text.trim().toUpperCase(),
        orderTotal: widget.orderTotal,
        userId: widget.userId,
      );

      if (result['success']) {
        try {
          final voucherData = result['data'] as Map<String, dynamic>;
          final discount =
              double.tryParse(
                voucherData['discountAmount']?.toString() ?? '0',
              ) ??
              0.0;

          setState(() {
            selectedVoucher = Voucher.fromJson(voucherData);
            discountAmount = discount;
            successMessage =
                'Áp dụng thành công! Giảm ${discountAmount.toStringAsFixed(0)} VND';
            errorMessage = null;
          });

          // Callback về parent
          widget.onVoucherApplied?.call({
            'voucher': selectedVoucher,
            'discountAmount': discountAmount,
            'finalTotal': widget.orderTotal - discountAmount,
          });
        } catch (e) {
          setState(() => errorMessage = 'Lỗi xử lý dữ liệu: $e');
        }
      } else {
        setState(() => errorMessage = result['message']);
      }
    } catch (e) {
      setState(() => errorMessage = 'Lỗi: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // Chọn voucher từ danh sách
  void _selectVoucher(Voucher voucher) {
    if (!voucher.isValid(widget.orderTotal)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voucher này không còn hợp lệ')),
      );
      return;
    }

    setState(() {
      selectedVoucher = voucher;
      discountAmount = voucher.calculateDiscount(widget.orderTotal);
      _codeController.text = voucher.code;
      successMessage =
          'Áp dụng thành công! Giảm ${discountAmount.toStringAsFixed(0)} VND';
      errorMessage = null;
    });

    widget.onVoucherApplied?.call({
      'voucher': selectedVoucher,
      'discountAmount': discountAmount,
      'finalTotal': widget.orderTotal - discountAmount,
    });
  }

  // Hủy voucher
  void _removeVoucher() {
    setState(() {
      selectedVoucher = null;
      discountAmount = 0;
      _codeController.clear();
      successMessage = null;
      errorMessage = null;
    });

    widget.onVoucherApplied?.call({
      'voucher': null,
      'discountAmount': 0,
      'finalTotal': widget.orderTotal,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chọn Voucher'), elevation: 0),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thông tin đơn hàng
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Tổng tiền đơn hàng:'),
                          Text(
                            '${widget.orderTotal.toStringAsFixed(0)} VND',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Form nhập mã
                    const Text(
                      'Nhập mã voucher',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codeController,
                            decoration: InputDecoration(
                              hintText: 'VD: SALE50',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabled: selectedVoucher == null,
                            ),
                            textCapitalization: TextCapitalization.characters,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: selectedVoucher == null
                              ? _validateVoucher
                              : _removeVoucher,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                          ),
                          child: Text(
                            selectedVoucher == null ? 'Kiểm tra' : 'Hủy',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Thông báo
                    if (errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          border: Border.all(color: Colors.red),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(child: Text(errorMessage!)),
                          ],
                        ),
                      ),
                    if (successMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(child: Text(successMessage!)),
                          ],
                        ),
                      ),

                    if (selectedVoucher != null) ...[
                      const SizedBox(height: 24),
                      _buildVoucherInfo(selectedVoucher!),
                    ],

                    const SizedBox(height: 24),

                    // Danh sách vouchers khả dụng
                    const Text(
                      'Vouchers khả dụng',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (availableVouchers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        alignment: Alignment.center,
                        child: const Text(
                          'Không có voucher khả dụng',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: availableVouchers.length,
                        itemBuilder: (context, index) {
                          final voucher = availableVouchers[index];
                          final isSelected =
                              selectedVoucher?.code == voucher.code;
                          return GestureDetector(
                            onTap: () => _selectVoucher(voucher),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.blue
                                      : Colors.grey.shade300,
                                  width: isSelected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                color: isSelected
                                    ? Colors.blue.shade50
                                    : Colors.white,
                              ),
                              child: _buildVoucherListItem(voucher, isSelected),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildVoucherInfo(Voucher voucher) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mã: ${voucher.code}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Giảm: ${discountAmount.toStringAsFixed(0)} VND',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (voucher.description != null) ...[
            const SizedBox(height: 4),
            Text(voucher.description!),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Thành tiền: ${widget.orderTotal.toStringAsFixed(0)} VND'),
              Text(
                '${(widget.orderTotal - discountAmount).toStringAsFixed(0)} VND',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoucherListItem(Voucher voucher, bool isSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              voucher.code,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${voucher.discountValue.toStringAsFixed(0)}${voucher.discountType == 'percent' ? '%' : ' VND'}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ),
          ],
        ),
        if (voucher.description != null) ...[
          const SizedBox(height: 4),
          Text(
            voucher.description!,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Đơn tối thiểu: ${voucher.minOrderAmount.toStringAsFixed(0)} VND',
          style: const TextStyle(fontSize: 12),
        ),
        if (voucher.expiryDate != null)
          Text(
            'HSD: ${voucher.expiryDate!.day}/${voucher.expiryDate!.month}/${voucher.expiryDate!.year}',
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}
