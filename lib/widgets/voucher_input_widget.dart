import 'package:flutter/material.dart';
import '../models/voucher.dart';
import '../services/voucher_service.dart';

class VoucherInputWidget extends StatefulWidget {
  final double orderTotal;
  final int userId;
  final Function(Map<String, dynamic>?) onVoucherChanged;
  final bool canRemove;

  const VoucherInputWidget({
    Key? key,
    required this.orderTotal,
    required this.userId,
    required this.onVoucherChanged,
    this.canRemove = true,
  }) : super(key: key);

  @override
  _VoucherInputWidgetState createState() => _VoucherInputWidgetState();
}

class _VoucherInputWidgetState extends State<VoucherInputWidget> {
  final TextEditingController _codeController = TextEditingController();
  Voucher? _selectedVoucher;
  double _discountAmount = 0;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _applyVoucher() async {
    if (_codeController.text.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập mã voucher');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
            _selectedVoucher = Voucher.fromJson(voucherData);
            _discountAmount = discount;
            _errorMessage = null;
          });

          widget.onVoucherChanged.call({
            'voucher': _selectedVoucher,
            'discountAmount': _discountAmount,
            'finalTotal': widget.orderTotal - _discountAmount,
          });
        } catch (e) {
          setState(() => _errorMessage = 'Lỗi xử lý dữ liệu: $e');
        }
      } else {
        setState(() => _errorMessage = result['message']);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Lỗi: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _removeVoucher() {
    setState(() {
      _selectedVoucher = null;
      _discountAmount = 0;
      _codeController.clear();
      _errorMessage = null;
    });

    widget.onVoucherChanged.call(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mã khuyến mãi',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        if (_selectedVoucher == null)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    hintText: 'Nhập mã voucher',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  enabled: !_isLoading,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoading ? null : _applyVoucher,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  backgroundColor: Colors.blue,
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue.shade600,
                          ),
                        ),
                      )
                    : const Text(
                        'Áp dụng',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ],
          )
        else
          _buildAppliedVoucher(),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              border: Border.all(color: Colors.red.shade300),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.error, color: Colors.red.shade600, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade600, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAppliedVoucher() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mã: ${_selectedVoucher!.code}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Giảm: ${_discountAmount.toStringAsFixed(0)} VND',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
              if (widget.canRemove)
                InkWell(
                  onTap: _removeVoucher,
                  child: Icon(
                    Icons.close,
                    color: Colors.red.shade600,
                    size: 20,
                  ),
                ),
            ],
          ),
          if (_selectedVoucher!.description != null) ...[
            const SizedBox(height: 8),
            Text(
              _selectedVoucher!.description!,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}

// ============================================
// MINI WIDGET - Hiển thị voucher đã áp dụng
// ============================================
class VoucherDisplayWidget extends StatelessWidget {
  final Voucher? voucher;
  final double discountAmount;
  final Function()? onRemove;

  const VoucherDisplayWidget({
    Key? key,
    this.voucher,
    this.discountAmount = 0,
    this.onRemove,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (voucher == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✓ ${voucher!.code}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Text(
                  'Giảm: ${discountAmount.toStringAsFixed(0)} VND',
                  style: const TextStyle(fontSize: 12, color: Colors.green),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, color: Colors.red, size: 20),
            ),
        ],
      ),
    );
  }
}

// ============================================
// VOUCHER CHIPS - Hiển thị danh sách vouchers
// ============================================
class VoucherChipsWidget extends StatelessWidget {
  final List<Voucher> vouchers;
  final Function(Voucher) onSelect;
  final Voucher? selectedVoucher;

  const VoucherChipsWidget({
    Key? key,
    required this.vouchers,
    required this.onSelect,
    this.selectedVoucher,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (vouchers.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: vouchers.length,
        itemBuilder: (context, index) {
          final voucher = vouchers[index];
          final isSelected = selectedVoucher?.code == voucher.code;

          return Padding(
            padding: EdgeInsets.only(
              left: index == 0 ? 0 : 8,
              right: index == vouchers.length - 1 ? 0 : 0,
            ),
            child: FilterChip(
              selected: isSelected,
              onSelected: (_) => onSelect(voucher),
              label: Text(
                '${voucher.code}: ${voucher.discountValue}${voucher.discountType == 'percent' ? '%' : 'K'}',
              ),
              backgroundColor: Colors.white,
              selectedColor: Colors.blue.shade100,
              side: BorderSide(
                color: isSelected ? Colors.blue : Colors.grey.shade300,
              ),
            ),
          );
        },
      ),
    );
  }
}
