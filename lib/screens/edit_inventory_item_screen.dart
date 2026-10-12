import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/inventory_item.dart';
import '../services/db_service.dart';
import '../services/api_service.dart';

class AddInventoryItemScreen extends StatefulWidget {
  final InventoryItem? item;

  const AddInventoryItemScreen({super.key, this.item});

  @override
  State<AddInventoryItemScreen> createState() => _AddInventoryItemScreenState();
}

class _AddInventoryItemScreenState extends State<AddInventoryItemScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _idController;
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _importPriceController;
  late TextEditingController _unitController;
  late TextEditingController _stockController;
  bool get _isEditing => widget.item != null;
  bool _processing = false;
  String? _imagePath;
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _idController = TextEditingController(text: widget.item?.id ?? '');
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _priceController = TextEditingController(
      text: widget.item?.price.toString() ?? '',
    );
    _importPriceController = TextEditingController(
      text: widget.item?.importPrice?.toString() ?? '',
    );
    _unitController = TextEditingController(text: widget.item?.unit ?? '');
    _stockController = TextEditingController(
      text: widget.item?.stockQuantity.toString() ?? '0',
    );
    _selectedCategoryId = widget.item?.categoryId;
    _loadCategories();
    if (_isEditing) {
      _idController.text = widget.item!.id;
      // load image path if any
      _imagePath = DBService.productImages().get(widget.item!.id);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService.fetchCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      if (mounted) setState(() => _categories = []);
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _importPriceController.dispose();
    _unitController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file != null) {
      setState(() => _imagePath = file.path);
    }
  }

  Future<void> _generateInternalCode() async {
    setState(() => _processing = true);
    try {
      final code = await DBService.generateInternalProductCode();
      _idController.text = code;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Đã tạo mã nội bộ $code')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không tạo được mã: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _processing = true);
    try {
      final id = _idController.text.trim();
      final name = _nameController.text.trim();
      final price = double.parse(_priceController.text.trim());
      final importPrice = double.parse(_importPriceController.text.trim());
      final unit = _unitController.text.trim();
      final qty = int.parse(_stockController.text.trim());

      if (_selectedCategoryId == null) {
        throw Exception('Vui lòng chọn danh mục');
      }

      if (_isEditing) {
        final existing = widget.item!;
        final newId = id;

        if (newId != existing.id) {
          throw Exception(
            'Không đổi mã ID khi sửa kho. Hãy tạo mặt hàng mới nếu cần mã khác.',
          );
        }

        final updated = InventoryItem(
          id: existing.id,
          name: name,
          price: price,
          importPrice: importPrice,
          unit: unit,
          stockQuantity: existing.stockQuantity,
          categoryId: _selectedCategoryId,
          imageUrl: existing.imageUrl,
        );

        await ApiService.updateInventoryItem(updated);
        await DBService.syncInventoryItemsFromApi();
        if (qty != existing.stockQuantity) {
          await DBService.adjustInventoryRemote(
            item: updated,
            actualQuantity: qty,
            note: 'Cập nhật tồn kho',
          );
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cập nhật kho thành công'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      } else {
        if (DBService.inventoryProducts().containsKey(id)) {
          throw Exception('Mã tồn kho đã tồn tại');
        }

        await DBService.createInventoryItemRemote(
          barcode: id,
          name: name,
          price: price,
          importPrice: importPrice,
          unit: unit,
          quantity: qty,
          categoryId: _selectedCategoryId,
          imagePath: _imagePath,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thêm vào kho thành công'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCategoryId =
        _categories.any((c) => c['category_id'] == _selectedCategoryId)
        ? _selectedCategoryId
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Chỉnh sửa Kho' : 'Thêm hàng vào Kho'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _idController,
                readOnly: _isEditing,
                decoration: const InputDecoration(
                  labelText: 'Mã vạch / Mã nội bộ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nhập mã vạch / mã nội bộ'
                    : null,
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _processing ? null : _generateInternalCode,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Tạo mã nội bộ'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên hàng',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Nhập tên' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Giá bán dự kiến',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Nhập giá' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _importPriceController,
                decoration: const InputDecoration(
                  labelText: 'Giá nhập',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Nhập giá nhập';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return 'Giá nhập phải lớn hơn 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: 'Đơn vị',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Nhập đơn vị' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(selectedCategoryId),
                initialValue: selectedCategoryId,
                decoration: const InputDecoration(
                  labelText: 'Danh mục sản phẩm',
                  border: OutlineInputBorder(),
                ),
                items: _categories
                    .map(
                      (c) => DropdownMenuItem<int>(
                        value: c['category_id'] as int,
                        child: Text(c['category_name'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategoryId = v),
                validator: (v) => v == null ? 'Vui lòng chọn danh mục' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stockController,
                readOnly: _isEditing,
                decoration: const InputDecoration(
                  labelText: 'Số lượng tồn (chỉ xem)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Nhập số lượng' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text('Chọn ảnh'),
                  ),
                  const SizedBox(width: 12),
                  if (_imagePath != null)
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: Image.file(File(_imagePath!), fit: BoxFit.cover),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _processing ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                  ),
                  child: _processing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(_isEditing ? 'Cập nhật' : 'Thêm vào kho'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
