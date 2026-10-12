import 'package:flutter/material.dart';

import '../models/employee_schedule_day.dart';
import '../models/work_shift.dart';
import '../repositories/work_shift_repository.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';

/// Lịch ca theo tháng — NV xem lịch; admin xếp lịch / chặn nghỉ-ốm.
class EmployeeShiftScheduleScreen extends StatefulWidget {
  final int employeeId;
  final String employeeName;
  final bool canManageShift;
  final bool isAdminScheduleMode;

  const EmployeeShiftScheduleScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.canManageShift = false,
    this.isAdminScheduleMode = false,
  });

  @override
  State<EmployeeShiftScheduleScreen> createState() =>
      _EmployeeShiftScheduleScreenState();
}

class _EmployeeShiftScheduleScreenState extends State<EmployeeShiftScheduleScreen> {
  late DateTime _month;
  bool _loading = true;
  String? _error;
  EmployeeScheduleMonth? _schedule;
  List<WorkShift> _shifts = [];

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
      final schedule = await ApiService.fetchEmployeeScheduleMonth(
        employeeId: widget.employeeId,
        year: _month.year,
        month: _month.month,
      );
      final shifts = await WorkShiftRepository.fetchShiftsForMonth(
        employeeId: widget.employeeId,
        year: _month.year,
        month: _month.month,
      );
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _shifts = shifts;
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

  Future<void> _setDayStatus(String workDate, String status) async {
    try {
      await ApiService.setEmployeeDayStatus(
        employeeId: widget.employeeId,
        workDate: workDate,
        dayStatus: status,
        setBy: DBService.currentUserId(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'clear'
                ? 'Đã cho phép bắt đầu ca'
                : 'Đã cập nhật lịch ngày $workDate',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  void _showDayEditor(EmployeeScheduleDay day) {
    if (!widget.isAdminScheduleMode) return;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ngày ${day.workDate.split('-').reversed.join('/')}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                day.isBlocked
                    ? (day.blockReason ?? 'Đang chặn bắt đầu ca')
                    : 'Full-time: mặc định được phép bắt đầu ca',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.sick, color: Colors.orange),
                title: const Text('Báo ốm — chặn bắt đầu ca'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setDayStatus(day.workDate, 'sick');
                },
              ),
              ListTile(
                leading: const Icon(Icons.beach_access, color: Colors.red),
                title: const Text('Xin nghỉ — chặn bắt đầu ca'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setDayStatus(day.workDate, 'leave');
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.grey),
                title: const Text('Admin chặn ca (khác)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setDayStatus(day.workDate, 'blocked');
                },
              ),
              if (day.isBlocked)
                ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: const Text('Cho phép làm lại (bỏ chặn)'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setDayStatus(day.workDate, 'clear');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _dayColor(EmployeeScheduleDay day) {
    if (day.isBlocked) {
      if (day.overrideStatus == 'sick') return Colors.orange.shade100;
      if (day.overrideStatus == 'leave') return Colors.red.shade100;
      return Colors.grey.shade300;
    }
    if (day.shift != null && day.shift!['end_time'] == null) {
      return Colors.blue.shade100;
    }
    if (day.shift != null) return Colors.green.shade50;
    if (day.defaultStatus == 'scheduled') return Colors.teal.shade50;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final schedule = _schedule;
    final days = schedule?.days ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Text(
          widget.isAdminScheduleMode
              ? 'Xếp lịch — ${widget.employeeName}'
              : 'Lịch ca — ${widget.employeeName}',
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
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
                if (schedule != null)
                  Text(
                    'Loại: ${schedule.employmentType == 'full_time' ? 'Full-time (mặc định được làm)' : 'Linh hoạt'}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            ),
          ),
          if (widget.isAdminScheduleMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _legend(Colors.teal.shade100, 'Được làm'),
                  const SizedBox(width: 8),
                  _legend(Colors.red.shade100, 'Nghỉ'),
                  const SizedBox(width: 8),
                  _legend(Colors.orange.shade100, 'Ốm'),
                  const SizedBox(width: 8),
                  _legend(Colors.blue.shade100, 'Đang ca'),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (schedule != null) ...[
                          Row(
                            children: [
                              _statChip(
                                'Ngày được làm',
                                '${schedule.summary['scheduled_days'] ?? 0}',
                                Colors.teal,
                              ),
                              const SizedBox(width: 8),
                              _statChip(
                                'Ngày chặn',
                                '${schedule.summary['blocked_days'] ?? 0}',
                                Colors.red,
                              ),
                              const SizedBox(width: 8),
                              _statChip(
                                'Ca thực tế',
                                '${schedule.summary['worked_days'] ?? _shifts.length}',
                                Colors.blue,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Lịch tháng',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildCalendarGrid(days),
                        ],
                        const SizedBox(height: 20),
                        const Text(
                          'Ca đã chấm công',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_shifts.isEmpty)
                          const Text(
                            'Chưa có ca chấm công trong tháng này',
                            style: TextStyle(color: Colors.black54),
                          )
                        else
                          ..._shifts.map((s) {
                            final working = s.isOpen;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(s.workDate ?? '—'),
                                subtitle: Text(
                                  '${_formatTime(s.startTime)} → ${working ? 'đang làm' : _formatTime(s.endTime)}',
                                ),
                                trailing: Text(
                                  working ? 'Mở' : 'Xong',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: working
                                        ? Colors.blue.shade700
                                        : Colors.green.shade700,
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(List<EmployeeScheduleDay> days) {
    final firstWeekday =
        DateTime(_month.year, _month.month, 1).weekday; // 1=Mon
    final leading = firstWeekday % 7;
    final cells = <Widget>[
      ...['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'].map(
        (d) => Center(
          child: Text(
            d,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox());
    }
    for (final day in days) {
      final parts = day.workDate.split('-');
      final dayNum = int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0;
      cells.add(
        GestureDetector(
          onTap: widget.isAdminScheduleMode ? () => _showDayEditor(day) : null,
          child: Container(
            decoration: BoxDecoration(
              color: _dayColor(day),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: day.isBlocked ? Colors.red.shade300 : Colors.grey.shade200,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$dayNum',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: day.isBlocked ? Colors.red.shade900 : Colors.black87,
              ),
            ),
          ),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1.1,
      children: cells,
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _statChip(String label, String value, MaterialColor color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: color.shade900,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 10, color: color.shade800)),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? t) {
    if (t == null || t.isEmpty) return '—';
    return t.length >= 5 ? t.substring(0, 5) : t;
  }
}
