import 'package:flutter/material.dart';

// ✅ 1. Import DBService và User model
import '../services/db_service.dart';
import '../models/user.dart';

// ⛔ LƯU Ý:
// CSDL MySQL dùng vai trò: 'admin', 'employee', 'customer'.
// Vì vậy, màn hình này sẽ chỉ hiển thị 2 vai trò đó với số lượng
// nhân viên chính xác.
//
// Nó sẽ KHÔNG hiển thị "Owner (Chủ cửa hàng)" hay "Kho"
// như file hard-code cũ, vì các vai trò đó không tồn tại
// trong CSDL thật của bạn.

class RoleManagementScreen extends StatefulWidget {
  const RoleManagementScreen({super.key});

  @override
  State<RoleManagementScreen> createState() => _RoleManagementScreenState();
}

class _RoleManagementScreenState extends State<RoleManagementScreen> {
  bool _isLoading = true;
  int _ownerCount = 0; // Số lượng Quản lý (admin)
  int _staffCount = 0; // Số lượng Nhân viên (employee)

  @override
  void initState() {
    super.initState();
    // ✅ 2. Tải số lượng nhân viên thật khi màn hình mở
    _loadRoleCounts();
  }

  // ✅ 3. Hàm đọc CSDL Hive và đếm số lượng
  Future<void> _loadRoleCounts() async {
    setState(() => _isLoading = true);

    try {
      // Lấy tất cả user từ CSDL (giống hệt màn hình EmployeeManagement)
      final usersBox = DBService.users();
      final allUsers = usersBox.values.cast<User>().toList();

      // Đếm số lượng 'admin' và 'employee'
      final owners = allUsers.where((u) => u.role == 'admin').length;
      final staff = allUsers.where((u) => u.role == 'employee').length;

      // Cập nhật state để hiển thị
      setState(() {
        _ownerCount = owners;
        _staffCount = staff;
        _isLoading = false;
      });
    } catch (e) {
      // Xử lý nếu có lỗi
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi tải dữ liệu vai trò: $e')),
      );
    }
  }

  // Widget hiển thị mỗi dòng vai trò
  // (Lấy từ file hard-code cũ của bạn)
  Widget _buildRoleTile(
      {required String name,
        required String description,
        required int employeeCount}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Số nhân viên: $employeeCount', // ✅ 4. Hiển thị số lượng thật
              style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                  fontSize: 13),
            ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios,
            size: 16, color: Colors.grey),
        onTap: () {
          // ✅ 5. Không làm gì khi nhấn
          // (Vì vai trò được quản lý bên trong Employee,
          // không thể sửa/xoá từ màn hình này)
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quản lý vai trò',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // ✅ 6. Đã xoá nút Thêm (+)
          // Nút này vô nghĩa vì file 'add_role_screen.dart'
          // chỉ thêm vào danh sách giả, không thêm vào CSDL thật.
          // Vai trò được gán khi Thêm/Sửa Nhân viên.
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        // Thêm RefreshIndicator để kéo xuống tải lại
        onRefresh: _loadRoleCounts,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // ✅ 7. Hiển thị 2 vai trò thật từ CSDL
            _buildRoleTile(
              name: 'Quản lý',
              description: 'Quản lý sản phẩm, kho hàng, và xem báo cáo doanh thu.',
              employeeCount: _ownerCount, // Số lượng thật
            ),
            _buildRoleTile(
              name: 'Nhân viên',
              description: 'Thực hiện giao dịch thanh toán và xem sản phẩm.',
              employeeCount: _staffCount, // Số lượng thật
            ),
          ],
        ),
      ),
    );
  }
}
