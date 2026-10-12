import 'package:flutter/material.dart';

import '../models/work_shift.dart';
import '../repositories/work_shift_repository.dart';
import '../screens/employee_shift_schedule_screen.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';

/// Panel ca làm gọn — dùng trên Tài khoản / Chi tiết NV; lịch đầy đủ ở màn riêng.
class EmployeeShiftCard extends StatefulWidget {
  final int employeeId;
  final String employeeName;
  final bool canManageShift;
  final bool compact;
  final Map<String, dynamic>? initialSummary;
  final VoidCallback? onShiftChanged;

  const EmployeeShiftCard({
    super.key,
    required this.employeeId,
    this.employeeName = 'Nhân viên',
    this.canManageShift = true,
    this.compact = true,
    this.initialSummary,
    this.onShiftChanged,
  });

  @override
  State<EmployeeShiftCard> createState() => _EmployeeShiftCardState();
}

class _EmployeeShiftCardState extends State<EmployeeShiftCard> {
  bool _loading = true;
  bool _updating = false;
  String? _error;
  Map<String, dynamic>? _summary;
  WorkShiftDisplay? _display;

  @override
  void initState() {
    super.initState();
    if (widget.initialSummary != null) {
      _applySummary(widget.initialSummary!);
    } else {
      _load();
    }
  }

  void _applySummary(Map<String, dynamic> data) {
    _summary = data;
    _display = WorkShiftRepository.getDisplayShift(data);
    _loading = false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await WorkShiftRepository.fetchEmployeeSummary(
        widget.employeeId,
      );
      if (!mounted) return;
      setState(() => _applySummary(data));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _display = const WorkShiftDisplay();
        _loading = false;
      });
    }
  }

  Future<void> _start() async {
    setState(() => _updating = true);
    try {
      await WorkShiftRepository.startShift(widget.employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã bắt đầu ca làm')),
      );
      await _load();
      widget.onShiftChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _end() async {
    setState(() => _updating = true);
    try {
      await WorkShiftRepository.endShift(widget.employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã kết thúc ca làm')),
      );
      await _load();
      widget.onShiftChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _openSchedule() {
    final role =
        DBService.settings().get('current_role')?.toString().toLowerCase() ?? '';
    final isAdmin = role == 'admin';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeShiftScheduleScreen(
          employeeId: widget.employeeId,
          employeeName: widget.employeeName,
          canManageShift: widget.canManageShift && !isAdmin,
          isAdminScheduleMode: isAdmin,
        ),
      ),
    );
  }

  String _formatDate(dynamic value) {
    if (value == null) return '—';
    final dt = DateTime.tryParse(value.toString());
    if (dt == null) return value.toString();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _formatTime(dynamic value) {
    if (value == null || value.toString().isEmpty) return '—';
    final raw = value.toString();
    if (raw.length >= 5) return raw.substring(0, 5);
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final display = _display ?? const WorkShiftDisplay();
    final shift = display.displayShift;
    final working = display.isWorking;
    final hasData = display.hasAnyShift;

    if (widget.compact) {
      return _buildCompact(context, display, shift, working, hasData);
    }
    return _buildFull(context, display, shift, working, hasData);
  }

  Widget _buildCompact(
    BuildContext context,
    WorkShiftDisplay display,
    WorkShift? shift,
    bool working,
    bool hasData,
  ) {
    final statusColor = working
        ? Colors.blue.shade700
        : hasData
        ? Colors.green.shade700
        : Colors.grey.shade600;

    final timeLine = hasData
        ? '${_formatDate(shift?.workDate ?? _summary?['last_work_date'])} · '
            '${_formatTime(shift?.startTime ?? _summary?['start_time'])}'
            '${working ? ' → đang làm' : ' → ${_formatTime(shift?.endTime ?? _summary?['end_time'])}'}'
        : 'Chưa có ca — bấm bắt đầu khi vào làm';

    return Material(
      color: const Color(0xFFEEF4FF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _openSchedule,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.schedule, size: 20, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Ca làm',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      display.badgeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                timeLine,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (widget.canManageShift)
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: FilledButton.icon(
                          onPressed: _updating
                              ? null
                              : (working ? _end : _start),
                          icon: _updating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  working ? Icons.stop : Icons.play_arrow,
                                  size: 18,
                                ),
                          label: Text(working ? 'Kết thúc ca' : 'Bắt đầu ca'),
                          style: FilledButton.styleFrom(
                            backgroundColor: working
                                ? Colors.red.shade600
                                : const Color(0xFF1B7F4D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ),
                    ),
                  if (widget.canManageShift) const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: _openSchedule,
                        icon: const Icon(Icons.calendar_month_outlined, size: 18),
                        label: const Text('Lịch tháng'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFull(
    BuildContext context,
    WorkShiftDisplay display,
    WorkShift? shift,
    bool working,
    bool hasData,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCompact(context, display, shift, working, hasData),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _openSchedule,
          child: const Text('Xem tổng quan lịch ca theo tháng'),
        ),
      ],
    );
  }
}
