import 'package:flutter/material.dart';
import '../models/voucher.dart';
import '../services/voucher_service.dart';

class AdminVouchersScreen extends StatefulWidget {
  final String token;

  const AdminVouchersScreen({Key? key, required this.token}) : super(key: key);

  @override
  _AdminVouchersScreenState createState() => _AdminVouchersScreenState();
}

class _AdminVouchersScreenState extends State<AdminVouchersScreen> {
  List<Voucher> vouchers = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadVouchers();
  }

  Future<void> _loadVouchers() async {
    setState(() => isLoading = true);
    try {
      final loadedVouchers = await VoucherService.getAllVouchers(widget.token);
      setState(() => vouchers = loadedVouchers);
    } catch (e) {
      print('Lỗi: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteVoucher(int id) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa voucher'),
        content: const Text('Bạn chắc chắn muốn xóa?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await VoucherService.deleteVoucher(
                id,
                widget.token,
              );
              if (result['success']) {
                _loadVouchers();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Xóa thành công')));
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(result['message'])));
              }
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  Future<void> _viewUsage(int id) async {
    final usage = await VoucherService.getVoucherUsage(id, widget.token);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lịch sử sử dụng'),
        content: SizedBox(
          width: double.maxFinite,
          child: usage.isEmpty
              ? const Center(child: Text('Chưa có ai dùng'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: usage.length,
                  itemBuilder: (context, index) {
                    final item = usage[index];
                    return ListTile(
                      title: Text(item['full_name'] ?? 'N/A'),
                      subtitle: Text(item['email'] ?? ''),
                      trailing: Text('Lần: ${item['used_count'] ?? 0}'),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Vouchers'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadVouchers),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateVoucherScreen(token: widget.token),
            ),
          );
          if (result == true) {
            _loadVouchers();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : vouchers.isEmpty
          ? const Center(child: Text('Không có voucher'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: vouchers.length,
              itemBuilder: (context, index) {
                final voucher = vouchers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ExpansionTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                voucher.code,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                voucher.description ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: voucher.status == 'active'
                                ? Colors.green.shade100
                                : Colors.red.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            voucher.status == 'active'
                                ? 'Hoạt động'
                                : 'Vô hiệu',
                            style: TextStyle(
                              color: voucher.status == 'active'
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInfoRow(
                              'Loại giảm',
                              voucher.discountType == 'fixed'
                                  ? 'Cố định'
                                  : 'Theo %',
                            ),
                            _buildInfoRow(
                              'Giá trị',
                              '${voucher.discountValue}${voucher.discountType == 'percent' ? '%' : ' VND'}',
                            ),
                            _buildInfoRow(
                              'Đơn tối thiểu',
                              '${voucher.minOrderAmount} VND',
                            ),
                            if (voucher.maxDiscount != null)
                              _buildInfoRow(
                                'Giảm tối đa',
                                '${voucher.maxDiscount} VND',
                              ),
                            if (voucher.usageLimit != null)
                              _buildInfoRow(
                                'Giới hạn dùng',
                                '${voucher.usedCount}/${voucher.usageLimit} lần',
                              ),
                            if (voucher.expiryDate != null)
                              _buildInfoRow(
                                'Hết hạn',
                                '${voucher.expiryDate!.day}/${voucher.expiryDate!.month}/${voucher.expiryDate!.year}',
                              ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _viewUsage(voucher.id),
                                  icon: const Icon(Icons.history),
                                  label: const Text('Lịch sử dùng'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditVoucherScreen(
                                          token: widget.token,
                                          voucher: voucher,
                                        ),
                                      ),
                                    );
                                    if (result == true) {
                                      _loadVouchers();
                                    }
                                  },
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Sửa'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => _deleteVoucher(voucher.id),
                                  icon: const Icon(Icons.delete),
                                  label: const Text('Xóa'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// SCREEN TẠO VOUCHER MỚI
class CreateVoucherScreen extends StatefulWidget {
  final String token;

  const CreateVoucherScreen({Key? key, required this.token}) : super(key: key);

  @override
  _CreateVoucherScreenState createState() => _CreateVoucherScreenState();
}

class _CreateVoucherScreenState extends State<CreateVoucherScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController codeCtrl = TextEditingController();
  final TextEditingController descriptionCtrl = TextEditingController();
  final TextEditingController valueCtrl = TextEditingController();
  final TextEditingController minOrderCtrl = TextEditingController();
  final TextEditingController maxDiscountCtrl = TextEditingController();
  final TextEditingController limitCtrl = TextEditingController();
  final TextEditingController expiryCtrl = TextEditingController();

  String discountType = 'fixed';
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    minOrderCtrl.text = '0';
  }

  Future<void> _createVoucher() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final result = await VoucherService.createVoucher(
        code: codeCtrl.text,
        description: descriptionCtrl.text,
        discountType: discountType,
        discountValue: double.parse(valueCtrl.text),
        minOrderAmount: double.parse(minOrderCtrl.text),
        maxDiscount: maxDiscountCtrl.text.isNotEmpty
            ? double.parse(maxDiscountCtrl.text)
            : null,
        usageLimit: limitCtrl.text.isNotEmpty
            ? int.parse(limitCtrl.text)
            : null,
        expiryDate: expiryCtrl.text.isNotEmpty ? expiryCtrl.text : null,
        token: widget.token,
      );

      if (result['success']) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Tạo voucher thành công')));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['message'])));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo Voucher')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Mã voucher'),
                    validator: (v) => v!.isEmpty ? 'Nhập mã' : null,
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descriptionCtrl,
                    decoration: const InputDecoration(labelText: 'Mô tả'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: discountType,
                    decoration: const InputDecoration(labelText: 'Loại giảm'),
                    items: [
                      DropdownMenuItem(
                        value: 'fixed',
                        child: const Text('Cố định (VND)'),
                      ),
                      DropdownMenuItem(
                        value: 'percent',
                        child: const Text('Theo % (Phần trăm)'),
                      ),
                    ],
                    onChanged: (v) => setState(() => discountType = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: valueCtrl,
                    decoration: InputDecoration(
                      labelText: 'Giá trị giảm',
                      suffix: Text(discountType == 'percent' ? '%' : 'VND'),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Nhập giá trị' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: minOrderCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Đơn tối thiểu (VND)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Nhập giá trị' : null,
                  ),
                  const SizedBox(height: 12),
                  if (discountType == 'percent')
                    TextFormField(
                      controller: maxDiscountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Giảm tối đa (VND) - không bắt buộc',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: limitCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Giới hạn dùng (lần) - không bắt buộc',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: expiryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Hết hạn (YYYY-MM-DD) - không bắt buộc',
                      hintText: '2026-06-30',
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                      );
                      if (date != null) {
                        expiryCtrl.text =
                            '${date.year}-${date.month}-${date.day}';
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _createVoucher,
                    child: const Text('Tạo Voucher'),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    codeCtrl.dispose();
    descriptionCtrl.dispose();
    valueCtrl.dispose();
    minOrderCtrl.dispose();
    maxDiscountCtrl.dispose();
    limitCtrl.dispose();
    expiryCtrl.dispose();
    super.dispose();
  }
}

// SCREEN SỬA VOUCHER
class EditVoucherScreen extends StatefulWidget {
  final String token;
  final Voucher voucher;

  const EditVoucherScreen({
    Key? key,
    required this.token,
    required this.voucher,
  }) : super(key: key);

  @override
  _EditVoucherScreenState createState() => _EditVoucherScreenState();
}

class _EditVoucherScreenState extends State<EditVoucherScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController descriptionCtrl;
  late TextEditingController valueCtrl;
  late TextEditingController minOrderCtrl;
  late TextEditingController maxDiscountCtrl;
  late TextEditingController limitCtrl;
  late TextEditingController expiryCtrl;

  late String discountType;
  late String status;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    descriptionCtrl = TextEditingController(
      text: widget.voucher.description ?? '',
    );
    valueCtrl = TextEditingController(
      text: widget.voucher.discountValue.toString(),
    );
    minOrderCtrl = TextEditingController(
      text: widget.voucher.minOrderAmount.toString(),
    );
    maxDiscountCtrl = TextEditingController(
      text: widget.voucher.maxDiscount?.toString() ?? '',
    );
    limitCtrl = TextEditingController(
      text: widget.voucher.usageLimit?.toString() ?? '',
    );
    expiryCtrl = TextEditingController(
      text: widget.voucher.expiryDate != null
          ? '${widget.voucher.expiryDate!.year}-${widget.voucher.expiryDate!.month}-${widget.voucher.expiryDate!.day}'
          : '',
    );
    discountType = widget.voucher.discountType;
    status = widget.voucher.status;
  }

  Future<void> _updateVoucher() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      final result = await VoucherService.updateVoucher(
        id: widget.voucher.id,
        description: descriptionCtrl.text,
        discountType: discountType,
        discountValue: double.parse(valueCtrl.text),
        minOrderAmount: double.parse(minOrderCtrl.text),
        maxDiscount: maxDiscountCtrl.text.isNotEmpty
            ? double.parse(maxDiscountCtrl.text)
            : null,
        usageLimit: limitCtrl.text.isNotEmpty
            ? int.parse(limitCtrl.text)
            : null,
        expiryDate: expiryCtrl.text.isNotEmpty ? expiryCtrl.text : null,
        status: status,
        token: widget.token,
      );

      if (result['success']) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cập nhật thành công')));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result['message'])));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sửa Voucher')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Mã: ${widget.voucher.code}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionCtrl,
                    decoration: const InputDecoration(labelText: 'Mô tả'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: valueCtrl,
                    decoration: InputDecoration(
                      labelText: 'Giá trị giảm',
                      suffix: Text(discountType == 'percent' ? '%' : 'VND'),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Nhập giá trị' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: minOrderCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Đơn tối thiểu (VND)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Nhập giá trị' : null,
                  ),
                  const SizedBox(height: 12),
                  if (discountType == 'percent')
                    TextFormField(
                      controller: maxDiscountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Giảm tối đa (VND)',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: limitCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Giới hạn dùng (lần)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Trạng thái'),
                    items: [
                      DropdownMenuItem(
                        value: 'active',
                        child: const Text('Hoạt động'),
                      ),
                      DropdownMenuItem(
                        value: 'inactive',
                        child: const Text('Vô hiệu'),
                      ),
                    ],
                    onChanged: (v) => setState(() => status = v!),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _updateVoucher,
                    child: const Text('Cập nhật'),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    descriptionCtrl.dispose();
    valueCtrl.dispose();
    minOrderCtrl.dispose();
    maxDiscountCtrl.dispose();
    limitCtrl.dispose();
    expiryCtrl.dispose();
    super.dispose();
  }
}
