import 'package:flutter/material.dart';

import '../services/vietnam_address_service.dart';

class VietnamAddressForm extends StatefulWidget {
  final ValueChanged<String?> onAddressChanged;

  const VietnamAddressForm({super.key, required this.onAddressChanged});

  @override
  State<VietnamAddressForm> createState() => _VietnamAddressFormState();
}

class _VietnamAddressFormState extends State<VietnamAddressForm> {
  final _provinceController = TextEditingController();
  final _districtController = TextEditingController();
  final _wardController = TextEditingController();
  final _detailController = TextEditingController();

  List<_Province> _provinces = [];
  String? _provinceCode;
  String? _districtCode;
  String? _wardCode;
  bool _loading = true;
  String? _error;

  List<_District> get _districts {
    for (final province in _provinces) {
      if (province.code == _provinceCode) return province.districts;
    }
    return const [];
  }

  List<_Ward> get _wards {
    for (final district in _districts) {
      if (district.code == _districtCode) return district.wards;
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _loadAddressData();
  }

  @override
  void dispose() {
    _provinceController.dispose();
    _districtController.dispose();
    _wardController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _loadAddressData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final decoded = await VietnamAddressService.load();
      final provinces = decoded
          .whereType<Map>()
          .map((item) => _Province.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      if (!mounted) return;
      setState(() {
        _provinces = provinces;
        _loading = false;
      });
    } catch (_) {
      _showManualFallback();
    }
  }

  void _showManualFallback() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error =
          'Không tải được danh sách địa chỉ. Bạn vẫn có thể nhập thủ công.';
    });
  }

  String? _nameByCode<T>(
    List<T> values,
    String? code,
    String Function(T) codeOf,
    String Function(T) nameOf,
  ) {
    if (code == null) return null;
    for (final value in values) {
      if (codeOf(value) == code) return nameOf(value);
    }
    return null;
  }

  void _notifyAddress() {
    final detail = _detailController.text.trim();
    final province = _error == null
        ? _nameByCode(
            _provinces,
            _provinceCode,
            (item) => item.code,
            (item) => item.name,
          )
        : _provinceController.text.trim();
    final district = _error == null
        ? _nameByCode(
            _districts,
            _districtCode,
            (item) => item.code,
            (item) => item.name,
          )
        : _districtController.text.trim();
    final ward = _error == null
        ? _nameByCode(
            _wards,
            _wardCode,
            (item) => item.code,
            (item) => item.name,
          )
        : _wardController.text.trim();

    if (detail.isEmpty ||
        province == null ||
        province.isEmpty ||
        district == null ||
        district.isEmpty ||
        ward == null ||
        ward.isEmpty) {
      widget.onAddressChanged(null);
      return;
    }
    widget.onAddressChanged('$detail, $ward, $district, $province');
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Đang tải danh sách tỉnh/thành...')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(
            _error!,
            style: const TextStyle(
              color: Color(0xFFB45309),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loadAddressData,
            icon: const Icon(Icons.refresh),
            label: const Text('Tải lại danh sách'),
          ),
          const SizedBox(height: 12),
        ],
        if (_error == null) ...[
          DropdownButtonFormField<String>(
            initialValue: _provinceCode,
            isExpanded: true,
            decoration: _decoration('Tỉnh/Thành phố', Icons.map_outlined),
            items: _provinces
                .map(
                  (province) => DropdownMenuItem(
                    value: province.code,
                    child: Text(province.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _provinceCode = value;
                _districtCode = null;
                _wardCode = null;
              });
              _notifyAddress();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('district-$_provinceCode'),
            initialValue: _districtCode,
            isExpanded: true,
            decoration: _decoration('Quận/Huyện', Icons.location_city_outlined),
            items: _districts
                .map(
                  (district) => DropdownMenuItem(
                    value: district.code,
                    child: Text(district.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _provinceCode == null
                ? null
                : (value) {
                    setState(() {
                      _districtCode = value;
                      _wardCode = null;
                    });
                    _notifyAddress();
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('ward-$_districtCode'),
            initialValue: _wardCode,
            isExpanded: true,
            decoration: _decoration('Phường/Xã', Icons.place_outlined),
            items: _wards
                .map(
                  (ward) => DropdownMenuItem(
                    value: ward.code,
                    child: Text(ward.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _districtCode == null
                ? null
                : (value) {
                    setState(() => _wardCode = value);
                    _notifyAddress();
                  },
          ),
        ] else ...[
          TextField(
            controller: _provinceController,
            decoration: _decoration('Tỉnh/Thành phố', Icons.map_outlined),
            onChanged: (_) => _notifyAddress(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _districtController,
            decoration: _decoration('Quận/Huyện', Icons.location_city_outlined),
            onChanged: (_) => _notifyAddress(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wardController,
            decoration: _decoration('Phường/Xã', Icons.place_outlined),
            onChanged: (_) => _notifyAddress(),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _detailController,
          decoration: _decoration(
            'Địa chỉ chi tiết',
            Icons.home_work_outlined,
          ).copyWith(hintText: 'Số nhà, tên đường, tòa nhà...'),
          minLines: 1,
          maxLines: 2,
          onChanged: (_) => _notifyAddress(),
        ),
      ],
    );
  }
}

class _Province {
  final String code;
  final String name;
  final List<_District> districts;

  const _Province({
    required this.code,
    required this.name,
    required this.districts,
  });

  factory _Province.fromJson(Map<String, dynamic> json) {
    return _Province(
      code: json['code'].toString(),
      name: (json['name'] ?? '').toString(),
      districts: ((json['districts'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => _District.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class _District {
  final String code;
  final String name;
  final List<_Ward> wards;

  const _District({
    required this.code,
    required this.name,
    required this.wards,
  });

  factory _District.fromJson(Map<String, dynamic> json) {
    return _District(
      code: json['code'].toString(),
      name: (json['name'] ?? '').toString(),
      wards: ((json['wards'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => _Ward.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class _Ward {
  final String code;
  final String name;

  const _Ward({required this.code, required this.name});

  factory _Ward.fromJson(Map<String, dynamic> json) {
    return _Ward(
      code: json['code'].toString(),
      name: (json['name'] ?? '').toString(),
    );
  }
}
