import 'package:flutter/material.dart';

import '../models/user.dart';
import '../models/work_shift.dart';
import '../repositories/work_shift_repository.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import 'admin_schedule_overview_screen.dart';
import 'employee_detail_screen.dart';
import 'employee_shift_schedule_screen.dart';

enum _ShiftStatusFilter { all, working, completed, none }

enum _ShiftDateFilter { today, week, month, all }

class WorkShiftManagementScreen extends StatefulWidget {
  final String role;

  const WorkShiftManagementScreen({super.key, required this.role});

  @override
  State<WorkShiftManagementScreen> createState() =>
      _WorkShiftManagementScreenState();
}

class _WorkShiftManagementScreenState extends State<WorkShiftManagementScreen> {
  static const Color _primaryGreen = Color(0xFF1B7F4D);

  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  bool _updating = false;
  String? _error;
  List<User> _employees = [];
  List<WorkShift> _shifts = [];
  _ShiftStatusFilter _statusFilter = _ShiftStatusFilter.all;
  _ShiftDateFilter _dateFilter = _ShiftDateFilter.all;
  String _query = '';

  bool get _isAdmin => widget.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await DBService.syncUsersFromApi();
      final currentUserId = DBService.currentUserId();
      final isEmployee = widget.role == 'employee';
      final users = DBService.users().values.cast<User>().where((user) {
        final isStaff = user.role.toLowerCase() == 'employee';
        if (!isStaff) return false;
        if (isEmployee) return user.userId == currentUserId;
        return true;
      }).toList();

      final shifts = await WorkShiftRepository.getAllShifts();

      if (!mounted) return;
      setState(() {
        _employees = users;
        _shifts = isEmployee && currentUserId != null
            ? shifts.where((s) => s.employeeId == currentUserId).toList()
            : shifts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  List<_EmployeeShiftRow> get _baseRows {
    final shiftsByEmployee = <int, List<WorkShift>>{};
    for (final shift in _shifts) {
      shiftsByEmployee.putIfAbsent(shift.employeeId, () => []).add(shift);
    }

    final rows = _employees.map((employee) {
      final employeeShifts =
          shiftsByEmployee[employee.userId ?? -1] ?? const [];
      final displayShift = _pickDisplayShift(employeeShifts);
      return _EmployeeShiftRow(employee: employee, shift: displayShift);
    }).toList();

    rows.sort((a, b) {
      final aOpen = a.shift?.isOpen == true ? 1 : 0;
      final bOpen = b.shift?.isOpen == true ? 1 : 0;
      if (aOpen != bOpen) return bOpen.compareTo(aOpen);
      final aTime =
          a.shift?.startDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          b.shift?.startDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return rows;
  }

  List<_EmployeeShiftRow> get _rows =>
      _baseRows.where(_matchesFilters).toList();

  _ShiftSummary get _summary {
    final today = _dateOnly(DateTime.now());
    var working = 0;
    var completedToday = 0;
    var totalToday = 0;
    var notStartedToday = 0;

    for (final row in _baseRows) {
      final shift = row.shift;
      if (shift?.isOpen == true) working++;
      final date = shift?.startDateTime;
      final isToday = date != null && _dateOnly(date).isAtSameMomentAs(today);
      if (isToday) {
        totalToday++;
        if (shift?.isCompleted == true) completedToday++;
      }
      if (shift == null || !isToday) notStartedToday++;
    }

    return _ShiftSummary(
      working: working,
      completedToday: completedToday,
      notStartedToday: notStartedToday,
      totalToday: totalToday,
    );
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  WorkShift? _pickDisplayShift(List<WorkShift> shifts) {
    if (shifts.isEmpty) return null;
    final open = shifts.where((s) => s.isOpen).toList()
      ..sort(_compareShiftDesc);
    if (open.isNotEmpty) return open.first;
    final sorted = List<WorkShift>.from(shifts)..sort(_compareShiftDesc);
    return sorted.first;
  }

  int _compareShiftDesc(WorkShift a, WorkShift b) {
    final aTime = a.startDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.startDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final cmp = bTime.compareTo(aTime);
    if (cmp != 0) return cmp;
    return (b.id ?? 0).compareTo(a.id ?? 0);
  }

  bool _matchesFilters(_EmployeeShiftRow row) {
    final employee = row.employee;
    final shift = row.shift;
    final text = [
      employee.userId?.toString() ?? '',
      employee.fullName,
      employee.email,
      employee.phone,
    ].join(' ').toLowerCase();
    if (_query.isNotEmpty && !text.contains(_query)) return false;

    switch (_statusFilter) {
      case _ShiftStatusFilter.working:
        if (shift?.isOpen != true) return false;
        break;
      case _ShiftStatusFilter.completed:
        if (shift == null || shift.isOpen) return false;
        break;
      case _ShiftStatusFilter.none:
        if (shift != null) return false;
        break;
      case _ShiftStatusFilter.all:
        break;
    }

    if (shift == null) {
      return _dateFilter == _ShiftDateFilter.all ||
          _statusFilter == _ShiftStatusFilter.none;
    }

    return _matchesDateFilter(shift);
  }

  bool _matchesDateFilter(WorkShift shift) {
    if (_dateFilter == _ShiftDateFilter.all) return true;
    final start = shift.startDateTime;
    if (start == null) return false;
    final now = DateTime.now();
    final date = DateTime(start.year, start.month, start.day);
    final today = DateTime(now.year, now.month, now.day);
    switch (_dateFilter) {
      case _ShiftDateFilter.today:
        return date.isAtSameMomentAs(today);
      case _ShiftDateFilter.week:
        final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        return !date.isBefore(startOfWeek) && date.isBefore(endOfWeek);
      case _ShiftDateFilter.month:
        return start.year == now.year && start.month == now.month;
      case _ShiftDateFilter.all:
        return true;
    }
  }

  Future<void> _startShift(User employee) async {
    final employeeId = employee.userId;
    if (employeeId == null || _updating) return;
    setState(() => _updating = true);
    try {
      await WorkShiftRepository.startShift(employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã bắt đầu ca làm')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _endShift(User employee) async {
    final employeeId = employee.userId;
    if (employeeId == null || _updating) return;
    setState(() => _updating = true);
    try {
      await WorkShiftRepository.endShift(employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã kết thúc ca làm')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _openEmployeeDetail(User employee) async {
    await Navigator.of(context).push<bool?>(
      MaterialPageRoute(builder: (_) => EmployeeDetailScreen(user: employee)),
    );
    if (mounted) await _load();
  }

  Future<void> _openEmployeeSchedule(User employee) async {
    final employeeId = employee.userId;
    if (employeeId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeShiftScheduleScreen(
          employeeId: employeeId,
          employeeName: _employeeName(employee),
          isAdminScheduleMode: _isAdmin,
          canManageShift: !_isAdmin,
        ),
      ),
    );
    if (mounted) await _load();
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return 'Chưa có';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  String _formatTime(String? value) {
    if (value == null || value.isEmpty) return 'Chưa có';
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    }
    return value.length >= 5 ? value.substring(0, 5) : value;
  }

  String _durationText(WorkShift? shift) {
    if (shift == null) return 'Chưa có';
    if (shift.isOpen) return 'Đang làm';
    final duration = shift.completedDuration;
    if (duration == null) return 'Không xác định';
    final hours = duration.inMinutes ~/ 60;
    final minutes = duration.inMinutes % 60;
    if (hours <= 0) return '$minutes phút';
    return '$hours giờ ${minutes.toString().padLeft(2, '0')} phút';
  }

  String _employeeName(User user) =>
      user.fullName.isNotEmpty ? user.fullName : user.email;

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Text(_isAdmin ? 'Quản lý ca làm' : 'Ca làm của tôi'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          if (_isAdmin)
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminScheduleOverviewScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.calendar_month_outlined),
              tooltip: 'Xếp lịch tháng',
            ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: Column(
        children: [
          _filterHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _errorState()
                : rows.isEmpty
                ? _emptyState()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _shiftCard(rows[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterHeader() {
    final summary = _summary;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isAdmin
                ? 'Theo dõi trạng thái ca làm toàn bộ nhân viên'
                : 'Theo dõi ca làm và lịch tháng của bạn',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _summaryCard(
                'Đang làm',
                '${summary.working}',
                Icons.play_circle_outline,
                Colors.blue,
              ),
              const SizedBox(width: 8),
              _summaryCard(
                'Xong hôm nay',
                '${summary.completedToday}',
                Icons.check_circle_outline,
                Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _summaryCard(
                'Chưa bắt đầu',
                '${summary.notStartedToday}',
                Icons.schedule_outlined,
                Colors.orange,
              ),
              const SizedBox(width: 8),
              _summaryCard(
                'Ca hôm nay',
                '${summary.totalToday}',
                Icons.today_outlined,
                Colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Tìm theo tên hoặc mã nhân viên',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF6F7FB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _statusChip('Tất cả', _ShiftStatusFilter.all),
                _statusChip('Đang làm', _ShiftStatusFilter.working),
                _statusChip('Đã kết thúc', _ShiftStatusFilter.completed),
                _statusChip('Chưa có ca', _ShiftStatusFilter.none),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _dateChip('Hôm nay', _ShiftDateFilter.today),
                _dateChip('Tuần này', _ShiftDateFilter.week),
                _dateChip('Tháng này', _ShiftDateFilter.month),
                _dateChip('Tất cả', _ShiftDateFilter.all),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, _ShiftStatusFilter value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _statusFilter == value,
        onSelected: (_) {
          setState(() => _statusFilter = value);
        },
      ),
    );
  }

  Widget _dateChip(String label, _ShiftDateFilter value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _dateFilter == value,
        selectedColor: _primaryGreen.withValues(alpha: 0.16),
        checkmarkColor: _primaryGreen,
        onSelected: (_) {
          setState(() => _dateFilter = value);
        },
      ),
    );
  }

  Widget _summaryCard(
    String label,
    String value,
    IconData icon,
    MaterialColor color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.shade100),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color.shade900,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color.shade800, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftCard(_EmployeeShiftRow row) {
    final employee = row.employee;
    final shift = row.shift;
    final working = shift?.isOpen == true;
    final hasShift = shift != null;
    final statusText = working
        ? 'Đang làm'
        : hasShift
        ? 'Đã kết thúc'
        : 'Chưa có ca';
    final statusColor = working
        ? Colors.blue.shade700
        : hasShift
        ? Colors.green.shade700
        : Colors.orange.shade700;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: _primaryGreen.withValues(alpha: 0.12),
                  child: Text(
                    _employeeName(employee).trim().isEmpty
                        ? '?'
                        : _employeeName(employee).trim()[0].toUpperCase(),
                    style: const TextStyle(
                      color: _primaryGreen,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _employeeName(employee),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Mã NV: ${employee.userId ?? '-'}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusPill(statusText, statusColor),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _miniInfo(
                  'Ngày làm',
                  _formatDate(shift?.workDate),
                  Icons.event,
                ),
                _miniInfo(
                  'Giờ bắt đầu',
                  _formatTime(shift?.startTime),
                  Icons.login,
                ),
                _miniInfo(
                  'Giờ kết thúc',
                  working ? 'Đang làm' : _formatTime(shift?.endTime),
                  Icons.logout,
                ),
                _miniInfo(
                  'Tổng thời gian',
                  _durationText(shift),
                  Icons.timer_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _updating
                      ? null
                      : working
                      ? () => _endShift(employee)
                      : () => _startShift(employee),
                  icon: Icon(working ? Icons.stop_circle : Icons.play_circle),
                  label: Text(working ? 'Kết thúc ca' : 'Bắt đầu ca'),
                  style: FilledButton.styleFrom(
                    backgroundColor: working
                        ? Colors.red.shade600
                        : _primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openEmployeeSchedule(employee),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Lịch tháng'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openEmployeeDetail(employee),
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Chi tiết'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniInfo(String label, String value, IconData icon) {
    return Container(
      constraints: const BoxConstraints(minWidth: 142, maxWidth: 190),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 46,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 10),
            const Text(
              'Chưa có dữ liệu ca làm phù hợp',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Thử đổi bộ lọc hoặc bắt đầu ca cho nhân viên.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: Colors.red.shade400),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}

class _EmployeeShiftRow {
  final User employee;
  final WorkShift? shift;

  const _EmployeeShiftRow({required this.employee, required this.shift});
}

class _ShiftSummary {
  final int working;
  final int completedToday;
  final int notStartedToday;
  final int totalToday;

  const _ShiftSummary({
    required this.working,
    required this.completedToday,
    required this.notStartedToday,
    required this.totalToday,
  });
}
