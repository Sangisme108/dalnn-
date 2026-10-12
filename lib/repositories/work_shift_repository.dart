import 'package:hive_flutter/hive_flutter.dart';

import '../models/work_shift.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';

/// Lưu/đọc ca làm: ưu tiên REST API (MySQL), cache Hive khi offline/lỗi mạng.
class WorkShiftRepository {
  static Box? _cacheBox;

  static Future<Box> _box() async {
    if (_cacheBox != null && _cacheBox!.isOpen) return _cacheBox!;
    _cacheBox = await Hive.openBox(AppConstants.workShiftSummariesBox);
    return _cacheBox!;
  }

  static String _cacheKey(int employeeId) => 'employee_$employeeId';

  static Future<void> _writeCache(
    int employeeId,
    Map<String, dynamic> summary,
  ) async {
    final box = await _box();
    await box.put(_cacheKey(employeeId), {
      ...summary,
      '_cached_at': DateTime.now().toIso8601String(),
    });
  }

  static Map<String, dynamic>? _readCache(int employeeId) {
    if (_cacheBox == null || !_cacheBox!.isOpen) return null;
    final raw = _cacheBox!.get(_cacheKey(employeeId));
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  /// Tải summary nhân viên (gồm ca làm) từ API, fallback Hive.
  static Future<Map<String, dynamic>> fetchEmployeeSummary(
    int employeeId,
  ) async {
    try {
      final remote = await ApiService.fetchEmployeeSummary(employeeId);
      await _writeCache(employeeId, remote);
      return remote;
    } catch (e) {
      final cached = _readCache(employeeId);
      if (cached != null) {
        return Map<String, dynamic>.from(cached)
          ..['_from_cache'] = true
          ..['_cache_error'] = e.toString();
      }
      rethrow;
    }
  }

  static WorkShiftDisplay getDisplayShift(Map<String, dynamic> summary) {
    return WorkShiftDisplay.fromSummary(summary);
  }

  static Future<List<WorkShift>> getAllShifts({
    String status = 'all',
    String dateFilter = 'all',
  }) {
    return ApiService.fetchWorkShifts(status: status, dateFilter: dateFilter);
  }

  static Future<List<WorkShift>> getShiftsByEmployeeId(
    int employeeId, {
    String status = 'all',
    String dateFilter = 'all',
  }) {
    return ApiService.fetchWorkShifts(
      employeeId: employeeId,
      status: status,
      dateFilter: dateFilter,
    );
  }

  static Future<WorkShift?> getCurrentShiftByEmployeeId(int employeeId) async {
    final summary = await fetchEmployeeSummary(employeeId);
    return WorkShiftDisplay.fromSummary(summary).currentShift;
  }

  static Future<WorkShift?> getLatestShiftByEmployeeId(int employeeId) async {
    final summary = await fetchEmployeeSummary(employeeId);
    final display = WorkShiftDisplay.fromSummary(summary);
    return display.latestShift ?? display.currentShift;
  }

  static Future<WorkShiftDisplay> getDisplayShiftByEmployeeId(
    int employeeId,
  ) async {
    final summary = await fetchEmployeeSummary(employeeId);
    return getDisplayShift(summary);
  }

  static Future<Map<String, dynamic>> startShift(int employeeId) async {
    final data = await ApiService.startWorkShift(employeeId);
    await _mergeShiftIntoSummaryCache(employeeId, data, open: true);
    return data;
  }

  static Future<Map<String, dynamic>> endShift(int employeeId) async {
    final data = await ApiService.endWorkShift(employeeId);
    await _mergeShiftIntoSummaryCache(employeeId, data, open: false);
    return data;
  }

  static Future<List<WorkShift>> fetchShiftsForMonth({
    required int employeeId,
    required int year,
    required int month,
  }) async {
    try {
      return await ApiService.fetchEmployeeShiftsForMonth(
        employeeId: employeeId,
        year: year,
        month: month,
      );
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _mergeShiftIntoSummaryCache(
    int employeeId,
    Map<String, dynamic> shiftData, {
    required bool open,
  }) async {
    final shift = WorkShift.fromJson(shiftData);
    final cached = _readCache(employeeId) ?? <String, dynamic>{};
    final updated = Map<String, dynamic>.from(cached)
      ..['current_shift'] = open ? shift.toJson() : null
      ..['latest_shift'] = shift.toJson()
      ..['work_status'] = open ? 'working' : 'off'
      ..['last_work_date'] = shift.workDate
      ..['start_time'] = shift.startTime
      ..['end_time'] = open ? null : shift.endTime
      ..['_cached_at'] = DateTime.now().toIso8601String();
    await _writeCache(employeeId, updated);
  }
}
