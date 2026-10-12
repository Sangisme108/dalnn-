import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import 'customer_detail_screen.dart';

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<User> _customers = [];
  bool _isLoading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await DBService.syncUsersFromApi();
    } catch (e) {
      _error = e is ApiException ? e.message : e.toString();
    }

    final users = DBService.users().values.cast<User>().toList();
    users.sort((a, b) {
      final aName = a.fullName.isNotEmpty ? a.fullName : a.email;
      final bName = b.fullName.isNotEmpty ? b.fullName : b.email;
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    });

    if (!mounted) return;
    setState(() {
      _customers = users
          .where((user) => user.role.toLowerCase() == 'customer')
          .toList();
      _isLoading = false;
    });
  }

  List<User> get _filteredCustomers {
    if (_query.isEmpty) return _customers;
    return _customers.where((user) {
      final name = user.fullName.toLowerCase();
      final email = user.email.toLowerCase();
      final phone = user.phone.toLowerCase();
      final id = user.userId?.toString() ?? '';
      return name.contains(_query) ||
          email.contains(_query) ||
          phone.contains(_query) ||
          id.contains(_query);
    }).toList();
  }

  Widget _buildCustomerTile(User user) {
    final name = user.fullName.isNotEmpty ? user.fullName : user.email;
    final phone = user.phone.isNotEmpty ? user.phone : '-';
    final address = user.address.isNotEmpty ? user.address : 'Chưa có địa chỉ';
    final inactive = user.status.toLowerCase() == 'inactive';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        leading: CircleAvatar(
          backgroundColor: inactive ? Colors.grey : const Color(0xFF4C7FFF),
          child: const Icon(Icons.person_outline, color: Colors.white),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(user.email, style: const TextStyle(fontSize: 13)),
            Text(phone, style: const TextStyle(fontSize: 13)),
            Text(
              address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ],
        ),
        trailing: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: inactive ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                inactive ? 'Đã khóa' : 'Khách hàng',
                style: TextStyle(
                  color: inactive ? Colors.red.shade700 : Colors.green.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CustomerDetailScreen(user: user)),
          );
          if (mounted) await _loadCustomers();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customers = _filteredCustomers;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quản lý khách hàng',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Không tải được dữ liệu mới nhất. Đang dùng dữ liệu đã lưu.${_error == null ? '' : '\n$_error'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 45,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.black45, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Tìm kiếm khách hàng',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tải lại',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadCustomers,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : customers.isEmpty
                ? const Center(child: Text('Chưa có khách hàng phù hợp.'))
                : RefreshIndicator(
                    onRefresh: _loadCustomers,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: customers.length,
                      itemBuilder: (context, index) =>
                          _buildCustomerTile(customers[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
