const express = require('express');
const pool = require('../config/db');

const router = express.Router();

const BLOCKED_STATUSES = new Set(['leave', 'sick', 'blocked']);

function formatDateOnly(value) {
  if (!value) return null;
  if (value instanceof Date) {
    const y = value.getFullYear();
    const m = String(value.getMonth() + 1).padStart(2, '0');
    const d = String(value.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return String(value).slice(0, 10);
}

function formatTimeOnly(value) {
  if (!value) return null;
  if (value instanceof Date) {
    return `${String(value.getHours()).padStart(2, '0')}:${String(value.getMinutes()).padStart(2, '0')}:${String(value.getSeconds()).padStart(2, '0')}`;
  }
  return String(value).slice(0, 8);
}

async function getEmployee(employeeId) {
  const hasEmploymentType = await columnExists('users', 'employment_type');
  const [rows] = await pool.execute(
    `SELECT u.user_id, u.full_name,
            ${hasEmploymentType ? 'u.employment_type' : "'full_time' AS employment_type"},
            r.role_name
     FROM users u
     JOIN roles r ON r.role_id = u.role_id
     WHERE u.user_id = ? AND r.role_name = 'employee'`,
    [employeeId]
  );
  return rows[0] || null;
}

async function tableExists(tableName) {
  const [rows] = await pool.execute(
    `SELECT COUNT(*) AS count
     FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?`,
    [tableName]
  );
  return Number(rows[0]?.count || 0) > 0;
}

async function columnExists(tableName, columnName) {
  const [rows] = await pool.execute(
    `SELECT COUNT(*) AS count
     FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = ?
       AND COLUMN_NAME = ?`,
    [tableName, columnName]
  );
  return Number(rows[0]?.count || 0) > 0;
}

async function resolveDayStatus(employee, workDate, overrideRow, shiftRow) {
  const employmentType = employee.employment_type || 'full_time';
  const overrideStatus = overrideRow?.day_status || null;

  if (overrideStatus && BLOCKED_STATUSES.has(overrideStatus)) {
    return {
      work_date: workDate,
      employment_type: employmentType,
      default_status: employmentType === 'full_time' ? 'scheduled' : 'flexible',
      override_status: overrideStatus,
      note: overrideRow?.note || null,
      can_start_shift: false,
      block_reason:
        overrideStatus === 'sick'
          ? 'Nhân viên báo ốm — admin đã chặn ca'
          : overrideStatus === 'leave'
            ? 'Nhân viên xin nghỉ — admin đã chặn ca'
            : 'Admin chặn không cho bắt đầu ca',
      shift: shiftRow
        ? {
            shift_id: shiftRow.shift_id,
            start_time: formatTimeOnly(shiftRow.start_time),
            end_time: formatTimeOnly(shiftRow.end_time),
            status: shiftRow.status,
          }
        : null,
    };
  }

  const hasOpenShift = shiftRow && !shiftRow.end_time;
  return {
    work_date: workDate,
    employment_type: employmentType,
    default_status: employmentType === 'full_time' ? 'scheduled' : 'flexible',
    override_status: overrideStatus,
    note: overrideRow?.note || null,
    can_start_shift: true,
    block_reason: null,
    shift: shiftRow
      ? {
          shift_id: shiftRow.shift_id,
          start_time: formatTimeOnly(shiftRow.start_time),
          end_time: formatTimeOnly(shiftRow.end_time),
          status: shiftRow.status,
        }
      : null,
    day_label:
      employmentType === 'full_time'
        ? hasOpenShift
          ? 'Đang làm'
          : 'Được phép làm (full-time)'
        : 'Linh hoạt',
  };
}

async function assertCanStartShift(employeeId, workDate) {
  const employee = await getEmployee(employeeId);
  if (!employee) {
    return { ok: false, status: 404, message: 'Không tìm thấy nhân viên' };
  }

  if (!(await tableExists('employee_day_overrides'))) {
    return { ok: true };
  }

  const [overrides] = await pool.execute(
    `SELECT day_status, note FROM employee_day_overrides
     WHERE employee_id = ? AND work_date = ? LIMIT 1`,
    [employeeId, workDate]
  );

  const day = await resolveDayStatus(employee, workDate, overrides[0] || null, null);
  if (!day.can_start_shift) {
    return {
      ok: false,
      status: 403,
      message: day.block_reason || 'Hôm nay không được phép bắt đầu ca',
    };
  }
  return { ok: true };
}

router.get('/employee/:employeeId/month', async (req, res) => {
  try {
    const employeeId = Number(req.params.employeeId);
    const now = new Date();
    const year = Number(req.query.year) || now.getFullYear();
    const month = Number(req.query.month) || now.getMonth() + 1;

    const employee = await getEmployee(employeeId);
    if (!employee) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy nhân viên' });
    }

    const daysInMonth = new Date(year, month, 0).getDate();
    const startDate = `${year}-${String(month).padStart(2, '0')}-01`;
    const endDate = `${year}-${String(month).padStart(2, '0')}-${String(daysInMonth).padStart(2, '0')}`;

    let overrides = [];
    if (await tableExists('employee_day_overrides')) {
      const [rows] = await pool.execute(
        `SELECT * FROM employee_day_overrides
         WHERE employee_id = ? AND work_date BETWEEN ? AND ?`,
        [employeeId, startDate, endDate]
      );
      overrides = rows;
    }

    const [shifts] = await pool.execute(
      `SELECT * FROM work_shifts
       WHERE employee_id = ? AND shift_date BETWEEN ? AND ?
       ORDER BY shift_date, start_time`,
      [employeeId, startDate, endDate]
    );

    const overrideByDate = Object.fromEntries(
      overrides.map((o) => [formatDateOnly(o.work_date), o])
    );
    const shiftsByDate = {};
    for (const s of shifts) {
      const key = formatDateOnly(s.shift_date);
      if (!shiftsByDate[key]) shiftsByDate[key] = s;
    }

    const days = [];
    for (let d = 1; d <= daysInMonth; d++) {
      const workDate = `${year}-${String(month).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
      days.push(
        await resolveDayStatus(
          employee,
          workDate,
          overrideByDate[workDate] || null,
          shiftsByDate[workDate] || null
        )
      );
    }

    const blockedDays = days.filter((d) => !d.can_start_shift).length;
    const scheduledDays = days.filter((d) => d.can_start_shift && d.default_status === 'scheduled').length;

    res.json({
      success: true,
      data: {
        employee: {
          user_id: employee.user_id,
          full_name: employee.full_name,
          employment_type: employee.employment_type || 'full_time',
        },
        year,
        month,
        days,
        summary: {
          total_days: days.length,
          scheduled_days: scheduledDays,
          blocked_days: blockedDays,
          worked_days: shifts.length,
        },
      },
    });
  } catch (error) {
    console.error('employee-schedule month failed:', error);
    res.status(500).json({ success: false, message: 'Lỗi lấy lịch tháng', error: error.message });
  }
});

router.put('/employee/:employeeId/day', async (req, res) => {
  try {
    if (!(await tableExists('employee_day_overrides'))) {
      return res.status(500).json({
        success: false,
        message: 'Chưa có bảng employee_day_overrides. Chạy migration 2026-05-17-employee-schedule.sql',
      });
    }

    const employeeId = Number(req.params.employeeId);
    const workDate = req.body.work_date || req.body.workDate;
    const dayStatus = (req.body.day_status || req.body.dayStatus || '').toString().toLowerCase();
    const note = req.body.note || null;
    const setBy = req.body.set_by || req.body.setBy || null;

    if (!workDate) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập work_date' });
    }

    const employee = await getEmployee(employeeId);
    if (!employee) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy nhân viên' });
    }

    if (dayStatus === 'clear' || dayStatus === 'scheduled' || dayStatus === '') {
      await pool.execute(
        'DELETE FROM employee_day_overrides WHERE employee_id = ? AND work_date = ?',
        [employeeId, workDate]
      );
      const day = await resolveDayStatus(employee, workDate, null, null);
      return res.json({
        success: true,
        message: 'Đã bỏ chặn — nhân viên full-time được phép bắt đầu ca',
        data: day,
      });
    }

    if (!BLOCKED_STATUSES.has(dayStatus)) {
      return res.status(400).json({
        success: false,
        message: 'day_status phải là leave, sick, blocked hoặc clear',
      });
    }

    await pool.execute(
      `INSERT INTO employee_day_overrides (employee_id, work_date, day_status, note, set_by)
       VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE day_status = VALUES(day_status), note = VALUES(note), set_by = VALUES(set_by)`,
      [employeeId, workDate, dayStatus, note, setBy]
    );

    const [rows] = await pool.execute(
      'SELECT * FROM employee_day_overrides WHERE employee_id = ? AND work_date = ?',
      [employeeId, workDate]
    );
    const day = await resolveDayStatus(employee, workDate, rows[0], null);

    res.json({
      success: true,
      message:
        dayStatus === 'sick'
          ? 'Đã đánh dấu ngày nghỉ ốm'
          : dayStatus === 'leave'
            ? 'Đã đánh dấu ngày xin nghỉ'
            : 'Đã chặn bắt đầu ca',
      data: day,
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi cập nhật lịch', error: error.message });
  }
});

router.get('/overview/month', async (req, res) => {
  try {
    const now = new Date();
    const year = Number(req.query.year) || now.getFullYear();
    const month = Number(req.query.month) || now.getMonth() + 1;
    const daysInMonth = new Date(year, month, 0).getDate();
    const startDate = `${year}-${String(month).padStart(2, '0')}-01`;
    const endDate = `${year}-${String(month).padStart(2, '0')}-${String(daysInMonth).padStart(2, '0')}`;

    const hasEmploymentType = await columnExists('users', 'employment_type');
    const [employees] = await pool.execute(
      `SELECT u.user_id, u.full_name,
              ${hasEmploymentType ? 'u.employment_type' : "'full_time' AS employment_type"}
       FROM users u
       JOIN roles r ON r.role_id = u.role_id
       WHERE r.role_name = 'employee' AND u.status = 'active'
       ORDER BY u.full_name`
    );

    let blockedCounts = {};
    if (await tableExists('employee_day_overrides')) {
      const [rows] = await pool.execute(
        `SELECT employee_id, COUNT(*) AS blocked_days
         FROM employee_day_overrides
         WHERE work_date BETWEEN ? AND ?
           AND day_status IN ('leave','sick','blocked')
         GROUP BY employee_id`,
        [startDate, endDate]
      );
      blockedCounts = Object.fromEntries(rows.map((r) => [r.employee_id, Number(r.blocked_days)]));
    }

    res.json({
      success: true,
      data: {
        year,
        month,
        employees: employees.map((e) => ({
          user_id: e.user_id,
          full_name: e.full_name,
          employment_type: e.employment_type || 'full_time',
          blocked_days: blockedCounts[e.user_id] || 0,
        })),
      },
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi tổng quan lịch', error: error.message });
  }
});

module.exports = router;
module.exports.assertCanStartShift = assertCanStartShift;
