import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/product.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';

class ScanProductScreen extends StatefulWidget {
  const ScanProductScreen({super.key});

  @override
  State<ScanProductScreen> createState() => _ScanProductScreenState();
}

class _ScanProductScreenState extends State<ScanProductScreen> {
  final TextEditingController _manualCodeController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isCheckingPermission = true;
  bool _hasCameraPermission = false;
  bool _permissionPermanentlyDenied = false;
  PermissionStatus _cameraPermissionStatus = PermissionStatus.denied;
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  @override
  void dispose() {
    _manualCodeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    setState(() {
      _isCheckingPermission = true;
      _errorMessage = null;
    });

    final current = await Permission.camera.status;
    final status = current.isGranted
        ? current
        : await Permission.camera.request();
    if (!mounted) return;

    setState(() {
      _hasCameraPermission = status.isGranted;
      _cameraPermissionStatus = status;
      _permissionPermanentlyDenied =
          status.isPermanentlyDenied || status.isRestricted;
      _isCheckingPermission = false;
      _errorMessage = status.isGranted ? null : _cameraPermissionMessage(status);
    });

    if (status.isGranted) {
      await _scannerController.start();
    }
  }

  String _cameraPermissionMessage(PermissionStatus status) {
    if (status.isPermanentlyDenied || status.isRestricted) {
      return 'Quyền camera đã bị tắt. Vào Cài đặt > Sieuthimini để bật Camera, hoặc nhập mã thủ công bên dưới.';
    }
    return 'Bạn cần cấp quyền camera để quét mã sản phẩm, hoặc nhập mã thủ công bên dưới.';
  }

  String _cameraUnavailableMessage(Object? error) {
    final details = error?.toString().trim();
    if (details != null && details.isNotEmpty) {
      return 'Không mở được camera ($details). Hãy thử lại hoặc nhập mã thủ công.';
    }
    return 'Không mở được camera. Hãy thử lại hoặc nhập mã thủ công bên dưới.';
  }

  Future<void> _handleCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final product = await DBService.findSaleProductByCode(code);
      if (product.stockQuantity <= 0) {
        throw ApiException('Sản phẩm đã hết hàng');
      }
      if (!mounted) return;
      Navigator.of(context).pop<Product>(product);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : e.toString();
      setState(() {
        _errorMessage = message.contains('Không tìm thấy')
            ? 'Không tìm thấy sản phẩm'
            : message;
        _isProcessing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage!)));
    }
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isProcessing) return;
    String? code;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        code = value;
        break;
      }
    }
    if (code == null) return;
    _handleCode(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Quét mã sản phẩm'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildScannerCard(),
            const SizedBox(height: 16),
            _buildManualEntryCard(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _buildErrorState(_errorMessage!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScannerCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_scanner, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Camera quét mã',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_isProcessing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 1,
                child: _isCheckingPermission
                    ? const ColoredBox(
                        color: Colors.black12,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _hasCameraPermission
                    ? MobileScanner(
                        controller: _scannerController,
                        onDetect: _onBarcodeDetected,
                        errorBuilder: (context, error, child) {
                          return _CameraUnavailable(
                            message: _cameraUnavailableMessage(error),
                            onRetry: _requestCameraPermission,
                            onOpenSettings: _permissionPermanentlyDenied
                                ? openAppSettings
                                : null,
                          );
                        },
                      )
                    : _CameraUnavailable(
                        message: _errorMessage ??
                            _cameraPermissionMessage(_cameraPermissionStatus),
                        onRetry: _requestCameraPermission,
                        onOpenSettings: _permissionPermanentlyDenied
                            ? openAppSettings
                            : null,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualEntryCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Nhập mã thủ công',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manualCodeController,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Mã vạch / Mã nội bộ',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
                border: OutlineInputBorder(),
              ),
              onSubmitted: _handleCode,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _handleCode(_manualCodeController.text),
                icon: const Icon(Icons.search),
                label: const Text('Tìm và thêm vào giỏ'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade400,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: Colors.red.shade800)),
          ),
        ],
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onOpenSettings;

  const _CameraUnavailable({
    required this.message,
    required this.onRetry,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              child: const Text('Thử lại'),
            ),
            if (onOpenSettings != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onOpenSettings,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                ),
                child: const Text('Mở cài đặt'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
