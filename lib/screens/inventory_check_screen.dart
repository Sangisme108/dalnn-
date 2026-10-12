// lib/screens/inventory_check_screen.dart (ĐÃ CẬP NHẬT LOGIC TÌM KIẾM)
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/inventory_item.dart';
import '../services/db_service.dart';

class InventoryCheckScreen extends StatefulWidget {
  const InventoryCheckScreen({super.key});

  @override
  State<InventoryCheckScreen> createState() => _InventoryCheckScreenState();
}

class _InventoryCheckScreenState extends State<InventoryCheckScreen> {
  final _productSearchController = TextEditingController();
  final _actualQuantityController = TextEditingController();
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  InventoryItem? _selectedItem;
  int _systemStock = 0;
  int _difference = 0;

  @override
  void initState() {
    super.initState();
    _productSearchController.addListener(_searchProduct);
    _actualQuantityController.addListener(_calculateDifference);
  }

  @override
  void dispose() {
    _productSearchController.removeListener(_searchProduct);
    _actualQuantityController.removeListener(_calculateDifference);
    _productSearchController.dispose();
    _actualQuantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // HÀM TÌM KIẾM VÀ HIỂN THỊ TỒN KHO HỆ THỐNG
  void _searchProduct() {
    final query = _productSearchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _selectedItem = null;
        _systemStock = 0;
        _actualQuantityController.clear();
        _difference = 0;
      });
      return;
    }

    final Box<InventoryItem> box = DBService.inventoryProducts();
    final lowerQuery = query.toLowerCase();

    // Prefer exact id match first (case-insensitive)
    InventoryItem? found;
    for (final it in box.values) {
      if (it.id.toLowerCase() == lowerQuery) {
        found = it;
        break;
      }
    }

    // Fallback to name/id contains
    if (found == null) {
      for (final it in box.values) {
        if (it.name.toLowerCase().contains(lowerQuery) ||
            it.id.toLowerCase().contains(lowerQuery)) {
          found = it;
          break;
        }
      }
    }

    setState(() {
      _selectedItem = found;
      if (found != null) {
        _systemStock = found.stockQuantity;
        _calculateDifference();
      } else {
        _systemStock = 0;
        _difference = 0;
      }
    });
  }

  // HÀM TÍNH TOÁN CHÊNH LỆCH
  void _calculateDifference() {
    if (_selectedItem == null) {
      setState(() => _difference = 0);
      return;
    }

    final int actualQuantity =
        int.tryParse(_actualQuantityController.text) ?? 0;
    setState(() {
      // Chênh lệch = Số lượng thực tế - Số lượng hệ thống
      _difference = actualQuantity - _systemStock;
    });
  }

  // HÀM XÁC NHẬN ĐIỀU CHỈNH KHO
  void _onConfirmCheck() async {
    if (!_formKey.currentState!.validate() || _selectedItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn mặt hàng và nhập đủ thông tin.'),
        ),
      );
      return;
    }

    final int actualQuantity =
        int.tryParse(_actualQuantityController.text) ?? 0;

    // 1. Chỉ cập nhật nếu có chênh lệch
    if (_difference == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không có chênh lệch, không cần điều chỉnh.'),
        ),
      );
      Navigator.pop(context);
      return;
    }

    try {
      final item = _selectedItem!;

      await DBService.adjustInventoryRemote(
        item: item,
        actualQuantity: actualQuantity,
        note: _noteController.text.trim(),
      );

      // 3. Thông báo
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Điều chỉnh tồn kho thành công! Chênh lệch: $_difference ${item.unit}',
          ),
          backgroundColor: _difference > 0 ? Colors.green : Colors.red,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi điều chỉnh kho: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Color differenceColor = _difference == 0
        ? Colors.black54
        : (_difference > 0 ? Colors.green : Colors.red);
    String differenceText = _difference == 0
        ? '0'
        : (_difference > 0 ? '+$_difference' : '$_difference');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Kiểm kê',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black87,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Trường Tìm kiếm sản phẩm
              const Text(
                'Tìm kiếm sản phẩm',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _productSearchController,
                decoration: InputDecoration(
                  hintText: 'Nhập tên hoặc mã vạch / mã nội bộ...',
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: _selectedItem != null
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                ),
              ),

              if (_selectedItem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Text(
                    'Đơn vị: ${_selectedItem!.unit}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                )
              else if (_productSearchController.text.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Không tìm thấy sản phẩm.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),

              const SizedBox(height: 20),

              // Trường Tồn kho hệ thống
              const Text(
                'Tồn kho hệ thống',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                height: 50,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  _selectedItem != null
                      ? '$_systemStock ${_selectedItem!.unit}'
                      : '...',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Trường Số lượng thực tế
              const Text(
                'Số lượng thực tế',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _actualQuantityController,
                keyboardType: TextInputType.number,
                enabled:
                    _selectedItem !=
                    null, // Chỉ cho phép nhập khi đã chọn mặt hàng
                decoration: InputDecoration(
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) {
                  final int? quantity = int.tryParse(val ?? '');
                  if (_selectedItem != null &&
                      (quantity == null || quantity < 0)) {
                    return 'Vui lòng nhập Số lượng thực tế hợp lệ.';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Trường Chênh lệch
              const Text(
                'Chênh lệch (Thực tế - Hệ thống)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                height: 50,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  differenceText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: differenceColor,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Trường Ghi chú/Lý do chênh lệch
              const Text(
                'Ghi chú/Lý do chênh lệch',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _noteController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Ghi chú về lý do chênh lệch...',
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Nút Xác nhận điều chỉnh
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _selectedItem != null ? _onConfirmCheck : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Xác nhận điều chỉnh',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
