// lib/screens/import_inventory_screen.dart (ĐÃ CHỈNH SỬA)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/inventory_item.dart'; // <<< IMPORT InventoryItem
import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/product_asset_resolver.dart';
import '../services/db_service.dart'; // <<< Đảm bảo bạn có DBService và hàm inventoryHistory()

class ImportInventoryScreen extends StatefulWidget {
  const ImportInventoryScreen({super.key});

  @override
  State<ImportInventoryScreen> createState() => _ImportInventoryScreenState();
}

class _ImportInventoryScreenState extends State<ImportInventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final _newFormKey = GlobalKey<FormState>();

  // New item controllers
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _importPriceController = TextEditingController();
  final TextEditingController _unitController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController(text: '0');
  final TextEditingController _categoryController = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ApiService.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _selectedCategoryId =
            _selectedCategoryId ??
            (categories.isNotEmpty ? _categoryIdOf(categories.first) : null);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _categories = [];
        _selectedCategoryId = null;
      });
    }
  }

  int? _categoryIdOf(Map<String, dynamic> category) {
    final id = category['category_id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '');
  }

  Future<void> _createCategory() async {
    _categoryController.clear();
    final formKey = GlobalKey<FormState>();
    final name = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Thêm danh mục mới'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: _categoryController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Tên danh mục',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return 'Nhập tên danh mục';
              final exists = _categories.any(
                (c) =>
                    c['category_name']?.toString().trim().toLowerCase() ==
                    value.toLowerCase(),
              );
              if (exists) return 'Danh mục đã tồn tại';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(
                  dialogContext,
                ).pop(_categoryController.text.trim());
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    setState(() => _processing = true);
    try {
      final created = await ApiService.createCategory(name);
      final createdId = _categoryIdOf(created);
      await _loadCategories();
      if (!mounted) return;
      setState(() {
        if (createdId != null) {
          _selectedCategoryId = createdId;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm danh mục "$name"'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi thêm danh mục: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  String? _pickedImagePath;
  bool _processing = false;
  bool _codeLookupLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    _idController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _importPriceController.dispose();
    _unitController.dispose();
    _qtyController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file != null) {
      setState(() => _pickedImagePath = file.path);
    }
  }

  Future<void> _openScanDialog() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            _InventoryCodeScannerScreen(initialCode: _searchController.text),
      ),
    );
    if (code != null && code.isNotEmpty) {
      await _lookupCode(code);
    }
  }

  Future<void> _generateInternalCode() async {
    setState(() => _codeLookupLoading = true);
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
      if (mounted) setState(() => _codeLookupLoading = false);
    }
  }

  Future<void> _lookupCode(String code) async {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) return;

    setState(() => _codeLookupLoading = true);
    try {
      final localItem = DBService.inventoryProducts().get(normalizedCode);
      if (localItem != null) {
        await _addToExisting(localItem);
        return;
      }

      final result = await ApiService.scanProductCode(normalizedCode);
      final inventoryMap = result['inventory_item'];
      if (inventoryMap is Map) {
        final item = InventoryItem.fromJson(
          Map<String, dynamic>.from(inventoryMap),
        );
        await _addToExisting(item);
        return;
      }

      final productMap = result['product'];
      if (productMap is Map) {
        final product = Product.fromJson(Map<String, dynamic>.from(productMap));
        _idController.text = product.barcode ?? normalizedCode;
        _nameController.text = product.name;
        _priceController.text = product.price.toStringAsFixed(0);
        _unitController.text = product.unit;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mã có sản phẩm bán hàng, hãy thêm vào kho'),
          ),
        );
        return;
      }
    } catch (_) {
      _idController.text = normalizedCode;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mã chưa tồn tại, đã điền vào form thêm hàng mới'),
        ),
      );
    } finally {
      if (mounted) setState(() => _codeLookupLoading = false);
    }
  }

  // --- HÀM GHI LỊCH SỬ CHO SẢN PHẨM ĐÃ CÓ ---
  Future<void> _addToExisting(InventoryItem item) async {
    final qtyController = TextEditingController(text: '1');
    final importPriceController = TextEditingController(
      text: item.importPrice?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nhập thêm vào: ${item.name}'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số lượng',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Nhập số lượng';
                  final n = int.tryParse(v);
                  if (n == null || n <= 0) return 'Số không hợp lệ';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: importPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Giá nhập',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Nhập giá nhập';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return 'Giá nhập phải lớn hơn 0';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop({
                  'quantity': int.parse(qtyController.text.trim()),
                  'importPrice': double.parse(
                    importPriceController.text.trim(),
                  ),
                });
              }
            },
            child: const Text('Nhập'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() => _processing = true);
      try {
        final quantity = result['quantity'] as int;
        final importPrice = result['importPrice'] as double;
        await DBService.importInventoryRemote(
          item: item,
          quantity: quantity,
          importPrice: importPrice,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã nhập $quantity vào ${item.name}'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi nhập hàng: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _processing = false);
      }
    }
  }

  // --- HÀM GHI LỊCH SỬ CHO SẢN PHẨM MỚI ---
  Future<void> _createNewInventoryItem() async {
    if (!_newFormKey.currentState!.validate()) return;
    setState(() => _processing = true);
    try {
      final id = _idController.text.trim();

      if (DBService.inventoryProducts().containsKey(id)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mã vạch / mã nội bộ đã tồn tại!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final name = _nameController.text.trim();
      final price = double.parse(_priceController.text.trim());
      final importPrice = double.parse(_importPriceController.text.trim());
      final unit = _unitController.text.trim();
      final qty = int.parse(_qtyController.text.trim());

      if (_selectedCategoryId == null) {
        throw Exception('Vui lòng chọn danh mục');
      }

      final saved = await DBService.createInventoryItemRemote(
        barcode: id,
        name: name,
        price: price,
        importPrice: importPrice,
        unit: unit,
        quantity: qty,
        categoryId: _selectedCategoryId,
        imagePath: _pickedImagePath,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm ${saved.name} vào kho với SL: $qty'),
          backgroundColor: Colors.green,
        ),
      );

      // Clear form
      _idController.clear();
      _nameController.clear();
      _priceController.clear();
      _importPriceController.clear();
      _unitController.clear();
      _qtyController.text = '0';
      _newFormKey.currentState!.reset();
      _pickedImagePath = null;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi thêm hàng mới: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Widget _buildInventoryThumbnail(InventoryItem item) {
    final storedRaw =
        (DBService.productImages().get(item.id) ?? item.imageUrl ?? '')
            .toString();
    final stored = ApiService.resolveBackendUrl(storedRaw);

    if (storedRaw.trim().startsWith('assets/')) {
      return _buildInventoryAsset(item, preferredAsset: storedRaw.trim());
    }

    if (stored.startsWith('http')) {
      return SizedBox(
        width: 56,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            stored,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildInventoryAsset(item),
          ),
        ),
      );
    }

    if (stored.isNotEmpty) {
      try {
        final file = File(stored);
        if (file.existsSync()) {
          return SizedBox(
            width: 56,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(file, fit: BoxFit.cover),
            ),
          );
        }
      } catch (_) {}
    }

    return _buildInventoryAsset(item);
  }

  Widget _buildInventoryAsset(InventoryItem item, {String? preferredAsset}) {
    return SizedBox(
      width: 56,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          preferredAsset ?? ProductAssetResolver.forInventoryItem(item),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset(
            ProductAssetResolver.defaultProductAsset,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  // ... (Phần UI build giữ nguyên)
  @override
  Widget build(BuildContext context) {
    // UI
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nhập hàng vào kho',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search & suggestions for existing products
            const Text(
              'Sản phẩm đã có trong kho',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Tìm theo tên hoặc mã vạch / mã nội bộ ...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _codeLookupLoading ? null : _openScanDialog,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Quét mã'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _codeLookupLoading
                        ? null
                        : () => _lookupCode(_searchController.text.trim()),
                    icon: const Icon(Icons.search),
                    label: const Text('Tìm mã'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ValueListenable để tự động cập nhật khi kho thay đổi
            SizedBox(
              height: 240,
              child: ValueListenableBuilder(
                valueListenable: DBService.inventoryProducts().listenable(),
                builder: (context, Box invBox, _) {
                  final allInventory = invBox.values.toList();

                  final query = _searchController.text.trim();
                  final displayList = allInventory
                      .where(
                        (s) =>
                            s is InventoryItem &&
                            (query.isEmpty ||
                                (s.name.toLowerCase().contains(
                                      query.toLowerCase(),
                                    ) ||
                                    s.id.toLowerCase().contains(
                                      query.toLowerCase(),
                                    ))),
                      )
                      .toList();

                  if (displayList.isEmpty) {
                    return const Center(
                      child: Text('Không tìm thấy sản phẩm phù hợp'),
                    );
                  }

                  return ListView.separated(
                    itemCount: displayList.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = displayList[index];
                      final id = item.id;
                      final name = item.name;
                      final stock = item.stockQuantity;
                      final unit = item.unit;
                      final leading = _buildInventoryThumbnail(item);

                      return ListTile(
                        leading: leading,
                        title: Text(name),
                        subtitle: Text(
                          'Mã vạch / Mã nội bộ: $id • Tồn: $stock $unit',
                        ),
                        trailing: ElevatedButton(
                          onPressed: _processing
                              ? null
                              : () {
                                  _addToExisting(item);
                                },
                          child: const Text('Nhập'),
                        ),
                        onTap: _processing
                            ? null
                            : () {
                                _addToExisting(item);
                              },
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Nhập hàng mới (Sản phẩm chưa có trong kho)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Form(
              key: _newFormKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _idController,
                    decoration: const InputDecoration(
                      labelText: 'Mã vạch / Mã nội bộ',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Nhập mã vạch / mã nội bộ'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _codeLookupLoading
                          ? null
                          : _generateInternalCode,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Tạo mã nội bộ'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Tên sản phẩm',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Nhập tên SP' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Giá bán dự kiến',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Nhập giá bán';
                      final n = double.tryParse(v);
                      if (n == null || n <= 0) return 'Số không hợp lệ';
                      return null;
                    },
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
                      if (n == null || n <= 0) {
                        return 'Giá nhập phải lớn hơn 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _unitController,
                    decoration: const InputDecoration(
                      labelText: 'Đơn vị tính (kg, chiếc, hộp...)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Nhập đơn vị' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _qtyController,
                    decoration: const InputDecoration(
                      labelText: 'Số lượng nhập (ban đầu)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Nhập số lượng';
                      final n = int.tryParse(v);
                      if (n == null || n < 0) return 'Số không hợp lệ';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey(_selectedCategoryId),
                    initialValue:
                        _categories.any(
                          (c) => _categoryIdOf(c) == _selectedCategoryId,
                        )
                        ? _selectedCategoryId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Danh mục sản phẩm',
                      border: OutlineInputBorder(),
                    ),
                    items: _categories
                        .map(
                          (c) => DropdownMenuItem<int>(
                            value: _categoryIdOf(c),
                            child: Text(c['category_name'].toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                    validator: (v) =>
                        v == null ? 'Vui lòng chọn danh mục' : null,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _processing ? null : _createCategory,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Thêm danh mục mới'),
                    ),
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
                      if (_pickedImagePath != null)
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: Image.file(
                            File(_pickedImagePath!),
                            fit: BoxFit.cover,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _processing ? null : _createNewInventoryItem,
                      child: _processing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Thêm vào kho'),
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
}

class _InventoryCodeScannerScreen extends StatefulWidget {
  final String initialCode;

  const _InventoryCodeScannerScreen({required this.initialCode});

  @override
  State<_InventoryCodeScannerScreen> createState() =>
      _InventoryCodeScannerScreenState();
}

class _InventoryCodeScannerScreenState
    extends State<_InventoryCodeScannerScreen> {
  late final TextEditingController _controller;
  final MobileScannerController _scannerController = MobileScannerController();
  bool _checkingPermission = true;
  bool _hasCameraPermission = false;
  bool _processing = false;
  String? _cameraMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCode);
    _requestCameraPermission();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    setState(() {
      _checkingPermission = true;
      _cameraMessage = null;
    });

    final current = await Permission.camera.status;
    final status = current.isGranted
        ? current
        : await Permission.camera.request();
    if (!mounted) return;

    setState(() {
      _hasCameraPermission = status.isGranted;
      _checkingPermission = false;
      _cameraMessage = status.isGranted
          ? null
          : 'Simulator có thể không hỗ trợ camera. Vui lòng nhập mã thủ công để demo.';
    });

    if (status.isGranted) {
      try {
        await _scannerController.start();
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _hasCameraPermission = false;
          _cameraMessage =
              'Simulator có thể không hỗ trợ camera. Vui lòng nhập mã thủ công để demo.';
        });
      }
    }
  }

  void _finish(String rawCode) {
    final code = rawCode.trim();
    if (code.isEmpty || _processing) return;
    _processing = true;
    Navigator.of(context).pop(code);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processing) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _finish(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét mã vạch'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: _checkingPermission
                    ? const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _hasCameraPermission
                    ? MobileScanner(
                        controller: _scannerController,
                        onDetect: _onDetect,
                        errorBuilder: (context, error, child) {
                          return _ScannerFallback(
                            message:
                                'Simulator có thể không hỗ trợ camera. Vui lòng nhập mã thủ công để demo.',
                            onRetry: _requestCameraPermission,
                          );
                        },
                      )
                    : _ScannerFallback(
                        message:
                            _cameraMessage ??
                            'Bạn cần cấp quyền camera để quét mã sản phẩm, hoặc nhập mã thủ công bên dưới.',
                        onRetry: _requestCameraPermission,
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: !_hasCameraPermission,
              decoration: const InputDecoration(
                labelText: 'Mã vạch / Mã nội bộ',
                helperText: 'Nhập mã thủ công để demo trên simulator',
                border: OutlineInputBorder(),
              ),
              onSubmitted: _finish,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _finish(_controller.text),
                icon: const Icon(Icons.search),
                label: const Text('Tìm mã'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerFallback extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ScannerFallback({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white, size: 44),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại camera'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
