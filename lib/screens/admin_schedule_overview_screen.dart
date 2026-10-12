import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'employee_shift_schedule_screen.dart';

/// Admin — tổng quan lịch ca tất cả nhân viên trong tháng.
class AdminScheduleOverviewScreen extends StatefulWidget {
  const AdminScheduleOverviewScreen({super.key});

  @override
  State<AdminScheduleOverviewScreen> createState() =>
      _AdminScheduleOverviewScreenState();
}

class _AdminScheduleOverviewScreenState extends State<AdminScheduleOverviewScreen> {
  late DateTime _month;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.fetchScheduleOverviewMonth(
        year: _month.year,
        month: _month.month,
      );
      if (!mounted) return;
      setState(() {
        _employees = list;
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

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Xếp lịch ca nhân viên'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        'Tháng ${_month.month}/${_month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Nhân viên full-time mặc định được phép bắt đầu ca. '
                  'Chạm từng người để đánh dấu nghỉ / ốm / chặn ca.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _employees.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final e = _employees[index];
                      final name = (e['full_name'] ?? '').toString();
                      final blocked = e['blocked_days'] ?? 0;
                      final type =
                          (e['employment_type'] ?? 'full_time').toString();
                      return Card(
                        elevation: 0,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade50,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            type == 'full_time'
                                ? 'Full-time · $blocked ngày chặn trong tháng'
                                : 'Linh hoạt · $blocked ngày chặn',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EmployeeShiftScheduleScreen(
                                  employeeId: e['user_id'] as int,
                                  employeeName: name,
                                  isAdminScheduleMode: true,
                                ),
                              ),
                            ).then((_) => _load());
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
