import '../utils/type_converters.dart';

/// Ca làm nhân viên — map từ API `work_shifts` / `employee-summary`.
class WorkShift {
  final int? id;
  final int employeeId;
  final String? employeeName;
  final String? employeeEmail;
  final String? workDate;
  final String? startTime;
  final String? endTime;
  final String status;
  final String? note;
  final String? createdAt;
  final String? updatedAt;

  const WorkShift({
    this.id,
    required this.employeeId,
    this.employeeName,
    this.employeeEmail,
    this.workDate,
    this.startTime,
    this.endTime,
    this.status = 'active',
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  factory WorkShift.fromJson(Map<String, dynamic> json) {
    return WorkShift(
      id: TypeConverters.toNullableInt(json['shift_id'] ?? json['id']),
      employeeId: TypeConverters.toInt(
        json['employee_id'] ?? json['employeeId'],
        defaultValue: 0,
      ),
      employeeName:
          (json['employee_name'] ??
                  json['employeeName'] ??
                  json['full_name'] ??
                  json['fullName'])
              ?.toString(),
      employeeEmail:
          (json['employee_email'] ?? json['employeeEmail'] ?? json['email'])
              ?.toString(),
      workDate: (json['shift_date'] ?? json['workDate'])?.toString(),
      startTime: (json['start_time'] ?? json['startTime'])?.toString(),
      endTime: (json['end_time'] ?? json['endTime'])?.toString(),
      status: (json['status'] ?? 'active').toString(),
      note: json['note']?.toString(),
      createdAt: (json['created_at'] ?? json['createdAt'])?.toString(),
      updatedAt: (json['updated_at'] ?? json['updatedAt'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'shift_id': id,
    'employee_id': employeeId,
    if (employeeName != null) 'employee_name': employeeName,
    if (employeeEmail != null) 'employee_email': employeeEmail,
    'shift_date': workDate,
    'start_time': startTime,
    'end_time': endTime,
    'status': status,
    'note': note,
    if (createdAt != null) 'created_at': createdAt,
    if (updatedAt != null) 'updated_at': updatedAt,
  };

  bool get isOpen {
    if (endTime != null && endTime!.isNotEmpty) return false;
    final s = status.toLowerCase();
    return s == 'active' || s == 'working';
  }

  bool get isCompleted {
    if (isOpen) return false;
    final s = status.toLowerCase();
    return s == 'completed' || s == 'closed';
  }

  DateTime? get startDateTime => _combineDateTime(workDate, startTime);

  DateTime? get endDateTime => _combineDateTime(workDate, endTime);

  Duration? get completedDuration {
    final start = startDateTime;
    final end = endDateTime;
    if (start == null || end == null || end.isBefore(start)) return null;
    return end.difference(start);
  }

  static DateTime? _combineDateTime(String? date, String? time) {
    if (date == null || date.isEmpty || time == null || time.isEmpty) {
      return null;
    }
    final normalizedTime = time.length >= 8 ? time.substring(0, 8) : time;
    return DateTime.tryParse('${date.substring(0, 10)} $normalizedTime');
  }
}

/// Dữ liệu đã chuẩn hóa để hiển thị section "Ca làm hiện tại".
class WorkShiftDisplay {
  final WorkShift? currentShift;
  final WorkShift? latestShift;
  final String workStatus;

  const WorkShiftDisplay({
    this.currentShift,
    this.latestShift,
    this.workStatus = 'off',
  });

  factory WorkShiftDisplay.fromSummary(Map<String, dynamic> summary) {
    WorkShift? parse(dynamic raw) {
      if (raw is! Map || raw.isEmpty) return null;
      return WorkShift.fromJson(Map<String, dynamic>.from(raw));
    }

    final current = parse(summary['current_shift']);
    final latest = parse(summary['latest_shift']);
    final status = (summary['work_status'] ?? 'off').toString();

    return WorkShiftDisplay(
      currentShift: current,
      latestShift: latest ?? current,
      workStatus: status,
    );
  }

  WorkShift? get displayShift => currentShift ?? latestShift;

  bool get isWorking =>
      currentShift != null && currentShift!.isOpen || workStatus == 'working';

  bool get hasAnyShift => displayShift != null;

  String get badgeLabel {
    if (isWorking) return 'Đang làm';
    if (hasAnyShift) return 'Đã kết thúc';
    return 'Chưa có ca';
  }
}
