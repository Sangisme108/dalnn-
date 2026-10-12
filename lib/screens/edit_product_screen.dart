import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../utils/product_asset_resolver.dart';
import '../widgets/product_image_widget.dart';

class EditProductScreen extends StatefulWidget {
  final Product product;
  const EditProductScreen({super.key, required this.product});

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _skuController;
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _unitController;
  late TextEditingController _stockController;
  late TextEditingController _descriptionController;
  late TextEditingController _highlightsController;
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  String _status = 'active';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _skuController = TextEditingController(text: p.barcode ?? p.id);
    _nameController = TextEditingController(text: p.name);
    _priceController = TextEditingController(text: p.price.toString());
    _unitController = TextEditingController(text: p.unit);
    _stockController = TextEditingController(text: p.stockQuantity.toString());
    _descriptionController = TextEditingController(text: p.description ?? '');
    _highlightsController = TextEditingController(text: p.highlights ?? '');
    _selectedCategoryId = p.categoryId;
    _status = p.status ?? 'active';
    _loadCategories();
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
    _skuController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    _stockController.dispose();
    _descriptionController.dispose();
    _highlightsController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng chọn danh mục')));
      return;
    }

    setState(() => _isSaving = true);

    final newName = _nameController.text.trim();
    final newPrice = double.parse(_priceController.text.trim());
    final newUnit = _unitController.text.trim();
    final newStock = int.parse(_stockController.text.trim());

    try {
      final sku = _skuController.text.trim();
      final importPrice = await DBService.fetchLatestImportPrice(sku);
      if (importPrice != null && newPrice < importPrice) {
        throw Exception('Giá bán không được nhỏ hơn giá nhập');
      }

      widget.product.name = newName;
      widget.product.price = newPrice;
      widget.product.unit = newUnit;
      widget.product.stockQuantity = newStock;
      widget.product.barcode = sku;
      widget.product.categoryId = _selectedCategoryId;
      widget.product.description = _descriptionController.text.trim();
      widget.product.highlights = _highlightsController.text.trim();
      widget.product.status = _status;
      final matched = _categories.where(
        (c) => c['category_id'] == _selectedCategoryId,
      );
      if (matched.isNotEmpty) {
        widget.product.categoryName = matched.first['category_name']
            ?.toString();
      }

      await DBService.updateProductRemote(widget.product);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật sản phẩm'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi lưu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chỉnh sửa sản phẩm'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 2,
                  child: ProductImageWidget(
                    product: p,
                    assetFallback: ProductAssetResolver.forProduct,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên sản phẩm *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nhập tên sản phẩm'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _skuController,
                decoration: const InputDecoration(
                  labelText: 'SKU / Mã nội bộ / Mã vạch',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nhập mã sản phẩm' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _selectedCategoryId,
                decoration: const InputDecoration(
                  labelText: 'Danh mục *',
                  border: OutlineInputBorder(),
                ),
                items: _categories
                    .map(
                      (c) => DropdownMenuItem<int>(
                        value: c['category_id'] as int?,
                        child: Text(c['category_name']?.toString() ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategoryId = v),
                validator: (v) => v == null ? 'Chọn danh mục' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unitController,
                decoration: const InputDecoration(
                  labelText: 'Đơn vị tính *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nhập đơn vị' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Giá bán (VNĐ) *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nhập giá';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return 'Giá phải là số dương';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stockController,
                decoration: const InputDecoration(
                  labelText: 'Số lượng tồn kho *',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Nhập tồn kho';
                  final n = int.tryParse(v);
                  if (n == null || n < 0) return 'Tồn kho không được âm';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Mô tả sản phẩm',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _highlightsController,
                decoration: const InputDecoration(
                  labelText: 'Đặc tính nổi bật / Thông số',
                  border: OutlineInputBorder(),
                  helperText: 'Lưu cục bộ; backend hiện chỉ đồng bộ mô tả',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'Trạng thái bán',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Còn bán')),
                  DropdownMenuItem(value: 'inactive', child: Text('Ngừng bán')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _status = v);
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Lưu thay đổi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
