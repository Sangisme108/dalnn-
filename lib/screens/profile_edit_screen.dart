import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/db_service.dart';
import '../services/vietnam_address_service.dart';
import '../models/user.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _provinceTextCtrl = TextEditingController();
  final _districtTextCtrl = TextEditingController();
  final _wardTextCtrl = TextEditingController();
  final _addressDetailCtrl = TextEditingController();
  List<_Province> _provinces = [];
  String? _selectedProvinceCode;
  String? _selectedDistrictCode;
  String? _selectedWardCode;
  bool _isLoadingAddressData = true;
  String? _addressDataError;
  String _gender = 'male';
  DateTime? _startDate;
  String? _avatarPath;
  bool _isSaving = false;

  User? _user;

  @override
  void initState() {
    super.initState();
    final settings = DBService.settings();
    final email = settings.get('current_user_email') as String?;
    if (email != null) {
      _user = DBService.users().values.cast<User?>().firstWhere(
        (u) => u?.email == email,
        orElse: () => null,
      );
      if (_user != null) {
        _fullNameCtrl.text = _user!.fullName;
        _phoneCtrl.text = _user!.phone;
        _parseSavedAddress(_user!.address);
        _gender = _user!.gender.isNotEmpty ? _user!.gender : _gender;
        _startDate = _user!.startDate;
        _avatarPath = _user!.avatarPath;
      }
    }
    _loadAddressData();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _provinceTextCtrl.dispose();
    _districtTextCtrl.dispose();
    _wardTextCtrl.dispose();
    _addressDetailCtrl.dispose();
    super.dispose();
  }

  List<_District> get _districts {
    final provinceCode = _selectedProvinceCode;
    if (provinceCode == null) return const [];
    return _provinces
        .firstWhere(
          (province) => province.code == provinceCode,
          orElse: () => const _Province(code: '', name: '', districts: []),
        )
        .districts;
  }

  List<_Ward> get _wards {
    final districtCode = _selectedDistrictCode;
    if (districtCode == null) return const [];
    return _districts
        .firstWhere(
          (district) => district.code == districtCode,
          orElse: () => const _District(code: '', name: '', wards: []),
        )
        .wards;
  }

  String? get _selectedProvinceName {
    final code = _selectedProvinceCode;
    if (code == null) {
      final manual = _provinceTextCtrl.text.trim();
      return manual.isEmpty ? null : manual;
    }
    for (final province in _provinces) {
      if (province.code == code) return province.name;
    }
    final manual = _provinceTextCtrl.text.trim();
    return manual.isEmpty ? null : manual;
  }

  String? get _selectedDistrictName {
    final code = _selectedDistrictCode;
    if (code == null) {
      final manual = _districtTextCtrl.text.trim();
      return manual.isEmpty ? null : manual;
    }
    for (final district in _districts) {
      if (district.code == code) return district.name;
    }
    final manual = _districtTextCtrl.text.trim();
    return manual.isEmpty ? null : manual;
  }

  String? get _selectedWardName {
    final code = _selectedWardCode;
    if (code == null) {
      final manual = _wardTextCtrl.text.trim();
      return manual.isEmpty ? null : manual;
    }
    for (final ward in _wards) {
      if (ward.code == code) return ward.name;
    }
    final manual = _wardTextCtrl.text.trim();
    return manual.isEmpty ? null : manual;
  }

  Future<void> _loadAddressData() async {
    setState(() {
      _isLoadingAddressData = true;
      _addressDataError = null;
    });

    try {
      final rawData = await VietnamAddressService.load();
      final provinces = rawData
          .whereType<Map>()
          .map((item) => _Province.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      if (!mounted) return;
      setState(() {
        _provinces = provinces;
        _matchSavedAddressToOptions();
        _isLoadingAddressData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addressDataError =
            'Không tải được danh sách tự động. Bạn vẫn có thể nhập địa chỉ thủ công.';
        _isLoadingAddressData = false;
      });
    }
  }

  void _parseSavedAddress(String address) {
    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.length >= 4) {
      _addressDetailCtrl.text = parts.sublist(0, parts.length - 3).join(', ');
      _pendingWardName = parts[parts.length - 3];
      _pendingDistrictName = parts[parts.length - 2];
      _pendingProvinceName = parts[parts.length - 1];
      _wardTextCtrl.text = _pendingWardName ?? '';
      _districtTextCtrl.text = _pendingDistrictName ?? '';
      _provinceTextCtrl.text = _pendingProvinceName ?? '';
    } else {
      _addressDetailCtrl.text = address;
    }
  }

  String? _pendingProvinceName;
  String? _pendingDistrictName;
  String? _pendingWardName;

  void _matchSavedAddressToOptions() {
    final provinceName = _pendingProvinceName;
    if (provinceName == null || _provinces.isEmpty) return;

    _Province? province;
    for (final item in _provinces) {
      if (_sameAddressName(item.name, provinceName)) {
        province = item;
        break;
      }
    }
    if (province == null) return;
    _selectedProvinceCode = province.code;

    final districtName = _pendingDistrictName;
    if (districtName == null) return;
    _District? district;
    for (final item in province.districts) {
      if (_sameAddressName(item.name, districtName)) {
        district = item;
        break;
      }
    }
    if (district == null) return;
    _selectedDistrictCode = district.code;

    final wardName = _pendingWardName;
    if (wardName == null) return;
    for (final item in district.wards) {
      if (_sameAddressName(item.name, wardName)) {
        _selectedWardCode = item.code;
        break;
      }
    }
  }

  bool _sameAddressName(String a, String b) {
    return _normalizeAddressName(a) == _normalizeAddressName(b);
  }

  String _normalizeAddressName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('thành phố ', '')
        .replaceAll('tỉnh ', '')
        .replaceAll('quận ', '')
        .replaceAll('huyện ', '')
        .replaceAll('thị xã ', '')
        .replaceAll('phường ', '')
        .replaceAll('xã ', '')
        .replaceAll('thị trấn ', '')
        .trim();
  }

  String _buildFullAddress() {
    final parts = [
      _addressDetailCtrl.text.trim(),
      _selectedWardName,
      _selectedDistrictName,
      _selectedProvinceName,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).toList();
    return parts.join(', ');
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.4),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
    );
    if (file != null) {
      setState(() => _avatarPath = file.path);
    }
  }

  Future<void> _save() async {
    if (_user == null) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final saved = await DBService.updateCurrentUserProfile(
        user: _user!,
        fullName: _fullNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _buildFullAddress(),
        password: null,
      );
      saved.gender = _gender;
      saved.startDate = _startDate;
      saved.avatarPath = _avatarPath;
      await saved.save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã cập nhật thông tin cá nhân'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi cập nhật: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now,
      firstDate: DateTime(1980),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Widget _addressFields() {
    if (_isLoadingAddressData) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          children: const [
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

    if (_addressDataError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: Color(0xFFB45309)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _addressDataError!,
                    style: const TextStyle(color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loadAddressData,
            icon: const Icon(Icons.refresh),
            label: const Text('Tải lại danh sách địa chỉ'),
          ),
          const SizedBox(height: 12),
          _manualAddressFields(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('province-${_provinces.length}'),
          initialValue: _selectedProvinceCode,
          isExpanded: true,
          decoration: _inputDecoration(
            label: 'Tỉnh/Thành phố',
            icon: Icons.map_outlined,
          ),
          items: _provinces
              .map(
                (province) => DropdownMenuItem(
                  value: province.code,
                  child: Text(province.name),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedProvinceCode = value;
              _selectedDistrictCode = null;
              _selectedWardCode = null;
            });
          },
          validator: (value) =>
              value == null ? 'Vui lòng chọn tỉnh/thành phố' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('district-$_selectedProvinceCode'),
          initialValue: _selectedDistrictCode,
          isExpanded: true,
          decoration: _inputDecoration(
            label: 'Quận/Huyện',
            icon: Icons.location_city_outlined,
          ),
          items: _districts
              .map(
                (district) => DropdownMenuItem(
                  value: district.code,
                  child: Text(district.name),
                ),
              )
              .toList(),
          onChanged: _selectedProvinceCode == null
              ? null
              : (value) {
                  setState(() {
                    _selectedDistrictCode = value;
                    _selectedWardCode = null;
                  });
                },
          validator: (value) =>
              value == null ? 'Vui lòng chọn quận/huyện' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('ward-$_selectedDistrictCode'),
          initialValue: _selectedWardCode,
          isExpanded: true,
          decoration: _inputDecoration(
            label: 'Phường/Xã',
            icon: Icons.place_outlined,
          ),
          items: _wards
              .map(
                (ward) =>
                    DropdownMenuItem(value: ward.code, child: Text(ward.name)),
              )
              .toList(),
          onChanged: _selectedDistrictCode == null
              ? null
              : (value) {
                  setState(() => _selectedWardCode = value);
                },
          validator: (value) =>
              value == null ? 'Vui lòng chọn phường/xã' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addressDetailCtrl,
          decoration: _inputDecoration(
            label: 'Địa chỉ chi tiết',
            hint: 'Số nhà, tên đường, tòa nhà...',
            icon: Icons.home_work_outlined,
          ),
          minLines: 1,
          maxLines: 2,
          validator: (v) => v == null || v.trim().isEmpty
              ? 'Vui lòng nhập địa chỉ chi tiết'
              : null,
        ),
      ],
    );
  }

  Widget _manualAddressFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _provinceTextCtrl,
          decoration: _inputDecoration(
            label: 'Tỉnh/Thành phố',
            hint: 'VD: Thành phố Hồ Chí Minh',
            icon: Icons.map_outlined,
          ),
          textCapitalization: TextCapitalization.words,
          validator: (v) => v == null || v.trim().isEmpty
              ? 'Vui lòng nhập tỉnh/thành phố'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _districtTextCtrl,
          decoration: _inputDecoration(
            label: 'Quận/Huyện',
            hint: 'VD: Quận 1',
            icon: Icons.location_city_outlined,
          ),
          textCapitalization: TextCapitalization.words,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Vui lòng nhập quận/huyện' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _wardTextCtrl,
          decoration: _inputDecoration(
            label: 'Phường/Xã',
            hint: 'VD: Phường Bến Nghé',
            icon: Icons.place_outlined,
          ),
          textCapitalization: TextCapitalization.words,
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Vui lòng nhập phường/xã' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addressDetailCtrl,
          decoration: _inputDecoration(
            label: 'Địa chỉ chi tiết',
            hint: 'Số nhà, tên đường, tòa nhà...',
            icon: Icons.home_work_outlined,
          ),
          minLines: 1,
          maxLines: 2,
          validator: (v) => v == null || v.trim().isEmpty
              ? 'Vui lòng nhập địa chỉ chi tiết'
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          'Chỉnh sửa hồ sơ',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: false,
        backgroundColor: const Color(0xFFF6F7F9),
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _profileHeader(),
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'Thông tin cá nhân',
                  icon: Icons.badge_outlined,
                  children: [
                    TextFormField(
                      controller: _fullNameCtrl,
                      decoration: _inputDecoration(
                        label: 'Họ tên',
                        icon: Icons.person_outline,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Vui lòng nhập họ tên'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCtrl,
                      decoration: _inputDecoration(
                        label: 'Số điện thoại',
                        icon: Icons.phone_outlined,
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Vui lòng nhập số điện thoại';
                        }
                        final phoneRegex = RegExp(r'^[0-9+\-\s]{8,15}$');
                        if (!phoneRegex.hasMatch(v.trim())) {
                          return 'Số điện thoại không hợp lệ';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  title: 'Địa chỉ nhận hàng',
                  icon: Icons.location_on_outlined,
                  children: [_addressFields()],
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  title: 'Thông tin bổ sung',
                  icon: Icons.tune_outlined,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: _inputDecoration(
                        label: 'Giới tính',
                        icon: Icons.wc_outlined,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'male', child: Text('Nam')),
                        DropdownMenuItem(value: 'female', child: Text('Nữ')),
                        DropdownMenuItem(value: 'other', child: Text('Khác')),
                      ],
                      onChanged: (v) => setState(() => _gender = v ?? 'male'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      readOnly: true,
                      decoration: _inputDecoration(
                        label: 'Ngày bắt đầu',
                        hint: _startDate == null
                            ? 'Chọn ngày'
                            : '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}',
                        icon: Icons.event_outlined,
                      ),
                      onTap: _pickStartDate,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Lưu thay đổi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileHeader() {
    final name = _fullNameCtrl.text.trim().isEmpty
        ? 'Hồ sơ của bạn'
        : _fullNameCtrl.text.trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                backgroundImage: _avatarPath != null
                    ? FileImage(File(_avatarPath!))
                    : null,
                child: _avatarPath == null
                    ? const Icon(Icons.person, size: 42, color: Colors.white)
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _pickAvatar,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.photo_camera_outlined,
                        size: 18,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Cập nhật thông tin liên hệ và địa chỉ giao hàng',
                  style: TextStyle(color: Colors.white70, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6FFFA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF0F766E), size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
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
    final districts = ((json['districts'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => _District.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    return _Province(
      code: json['code'].toString(),
      name: (json['name'] ?? '').toString(),
      districts: districts,
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
    final wards = ((json['wards'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => _Ward.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    return _District(
      code: json['code'].toString(),
      name: (json['name'] ?? '').toString(),
      wards: wards,
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
