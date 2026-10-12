class EmployeeScheduleDay {
  final String workDate;
  final String employmentType;
  final String defaultStatus;
  final String? overrideStatus;
  final String? note;
  final bool canStartShift;
  final String? blockReason;
  final String? dayLabel;
  final Map<String, dynamic>? shift;

  const EmployeeScheduleDay({
    required this.workDate,
    this.employmentType = 'full_time',
    this.defaultStatus = 'scheduled',
    this.overrideStatus,
    this.note,
    this.canStartShift = true,
    this.blockReason,
    this.dayLabel,
    this.shift,
  });

  factory EmployeeScheduleDay.fromJson(Map<String, dynamic> json) {
    return EmployeeScheduleDay(
      workDate: (json['work_date'] ?? '').toString(),
      employmentType: (json['employment_type'] ?? 'full_time').toString(),
      defaultStatus: (json['default_status'] ?? 'scheduled').toString(),
      overrideStatus: json['override_status']?.toString(),
      note: json['note']?.toString(),
      canStartShift: json['can_start_shift'] != false,
      blockReason: json['block_reason']?.toString(),
      dayLabel: json['day_label']?.toString(),
      shift: json['shift'] is Map
          ? Map<String, dynamic>.from(json['shift'] as Map)
          : null,
    );
  }

  bool get isBlocked => !canStartShift;

  String get displayStatus {
    if (overrideStatus == 'sick') return 'Nghỉ ốm';
    if (overrideStatus == 'leave') return 'Xin nghỉ';
    if (overrideStatus == 'blocked') return 'Chặn ca';
    if (shift != null && shift!['end_time'] == null) return 'Đang làm';
    if (defaultStatus == 'scheduled') return 'Full-time';
    return 'Linh hoạt';
  }
}

class EmployeeScheduleMonth {
  final int employeeId;
  final String employeeName;
  final String employmentType;
  final int year;
  final int month;
  final List<EmployeeScheduleDay> days;
  final Map<String, dynamic> summary;

  const EmployeeScheduleMonth({
    required this.employeeId,
    required this.employeeName,
    required this.employmentType,
    required this.year,
    required this.month,
    required this.days,
    required this.summary,
  });

  factory EmployeeScheduleMonth.fromJson(Map<String, dynamic> json) {
    final emp = json['employee'] is Map
        ? Map<String, dynamic>.from(json['employee'] as Map)
        : <String, dynamic>{};
    final dayList = (json['days'] as List?) ?? const [];
    return EmployeeScheduleMonth(
      employeeId: emp['user_id'] as int? ?? 0,
      employeeName: (emp['full_name'] ?? '').toString(),
      employmentType: (emp['employment_type'] ?? 'full_time').toString(),
      year: json['year'] as int? ?? DateTime.now().year,
      month: json['month'] as int? ?? DateTime.now().month,
      days: dayList
          .map(
            (e) => EmployeeScheduleDay.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      summary: json['summary'] is Map
          ? Map<String, dynamic>.from(json['summary'] as Map)
          : const {},
    );
  }
}
