const express = require('express');
const pool = require('../config/db');
const { assertCanStartShift } = require('./employeeSchedule.routes');

const router = express.Router();

function formatDateOnly(value) {
  if (!value) return null;
  if (value instanceof Date) {
    const year = value.getFullYear();
    const month = String(value.getMonth() + 1).padStart(2, '0');
    const day = String(value.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
  return String(value).slice(0, 10);
}

function formatTimeOnly(value) {
  if (!value) return null;
  if (value instanceof Date) {
    const hour = String(value.getHours()).padStart(2, '0');
    const minute = String(value.getMinutes()).padStart(2, '0');
    const second = String(value.getSeconds()).padStart(2, '0');
    return `${hour}:${minute}:${second}`;
  }
  return String(value).slice(0, 8);
}

function toShift(row) {
  if (!row) return null;
  return {
    shift_id: row.shift_id,
    employee_id: row.employee_id,
    employee_name: row.employee_name || row.full_name || null,
    employee_email: row.employee_email || row.email || null,
    shift_date: formatDateOnly(row.shift_date),
    start_time: formatTimeOnly(row.start_time),
    end_time: formatTimeOnly(row.end_time),
    status: row.status || (row.end_time ? 'closed' : 'active'),
    note: row.note,
    created_at: row.created_at || null,
    updated_at: row.updated_at || null,
  };
}

async function findEmployee(employeeId) {
  const [rows] = await pool.execute(
    `SELECT u.user_id, u.full_name, u.email, r.role_name
     FROM users u
     JOIN roles r ON r.role_id = u.role_id
     WHERE u.user_id = ?
       AND r.role_name = 'employee'
       AND u.status = 'active'
     LIMIT 1`,
    [employeeId]
  );
  return rows[0] || null;
}

async function findActiveShift(connection, employeeId) {
  const hasStatus = await workShiftHasStatus(connection);
  const activeWhere = hasStatus
    ? "end_time IS NULL AND status IN ('active', 'working', 'open')"
    : 'end_time IS NULL';
  const [rows] = await connection.execute(
    `SELECT *
     FROM work_shifts
     WHERE employee_id = ?
       AND ${activeWhere}
     ORDER BY shift_date DESC, start_time DESC, shift_id DESC
     LIMIT 1`,
    [employeeId]
  );
  return rows[0] || null;
}

async function workShiftHasStatus(connection) {
  const [rows] = await connection.execute(
    `SELECT COUNT(*) AS count
     FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'work_shifts'
       AND COLUMN_NAME = 'status'`
  );
  return Number(rows[0]?.count || 0) > 0;
}

router.get('/', async (req, res) => {
  try {
    const employeeId = Number(req.query.employee_id || req.query.employeeId);
    const status = (req.query.status || '').toString().toLowerCase();
    const dateFilter = (req.query.date_filter || req.query.dateFilter || 'all').toString();

    const params = [];
    const where = ["r.role_name = 'employee'"];
    if (employeeId) {
      where.push('u.user_id = ?');
      params.push(employeeId);
    }
    if (status === 'working') {
      where.push("ws.end_time IS NULL AND COALESCE(ws.status, 'working') IN ('active', 'working', 'open')");
    } else if (status === 'completed') {
      where.push("(ws.end_time IS NOT NULL OR COALESCE(ws.status, '') IN ('completed', 'closed'))");
    } else if (status === 'cancelled') {
      where.push("COALESCE(ws.status, '') IN ('cancelled', 'canceled')");
    }

    if (dateFilter === 'today') {
      where.push('ws.shift_date = CURDATE()');
    } else if (dateFilter === 'week') {
      where.push('YEARWEEK(ws.shift_date, 1) = YEARWEEK(CURDATE(), 1)');
    } else if (dateFilter === 'month') {
      where.push('YEAR(ws.shift_date) = YEAR(CURDATE()) AND MONTH(ws.shift_date) = MONTH(CURDATE())');
    }

    const [rows] = await pool.execute(
      `SELECT
         ws.*,
         u.full_name AS employee_name,
         u.email AS employee_email
       FROM work_shifts ws
       JOIN users u ON u.user_id = ws.employee_id
       JOIN roles r ON r.role_id = u.role_id
       WHERE ${where.join(' AND ')}
       ORDER BY ws.shift_date DESC, ws.start_time DESC, ws.shift_id DESC`,
      params
    );

    res.json({
      success: true,
      data: rows.map(toShift),
      meta: { total: rows.length },
    });
  } catch (error) {
    console.error('work-shifts all failed:', error);
    res.status(500).json({
      success: false,
      message: 'Lỗi lấy danh sách ca làm',
      error: error.message,
    });
  }
});

router.get('/employee/:employeeId', async (req, res) => {
  try {
    const employeeId = Number(req.params.employeeId);
    if (!employeeId) {
      return res.status(400).json({ success: false, message: 'employeeId không hợp lệ' });
    }

    const now = new Date();
    const year = Number(req.query.year) || now.getFullYear();
    const month = Number(req.query.month) || now.getMonth() + 1;

    const [rows] = await pool.execute(
      `SELECT
         ws.*,
         u.full_name AS employee_name,
         u.email AS employee_email
       FROM work_shifts ws
       JOIN users u ON u.user_id = ws.employee_id
       WHERE ws.employee_id = ?
         AND YEAR(ws.shift_date) = ?
         AND MONTH(ws.shift_date) = ?
       ORDER BY ws.shift_date DESC, ws.start_time DESC, ws.shift_id DESC`,
      [employeeId, year, month]
    );

    res.json({
      success: true,
      data: rows.map(toShift),
      meta: { year, month, total: rows.length },
    });
  } catch (error) {
    console.error('work-shifts list failed:', error);
    res.status(500).json({
      success: false,
      message: 'Lỗi lấy lịch ca làm',
      error: error.message,
    });
  }
});

router.post('/start', async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const employeeId = Number(req.body.employee_id);
    if (!employeeId) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập employee_id' });
    }

    const employee = await findEmployee(employeeId);
    if (!employee) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy nhân viên active' });
    }

    const today = new Date();
    const workDate = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    const scheduleCheck = await assertCanStartShift(employeeId, workDate);
    if (!scheduleCheck.ok) {
      return res.status(scheduleCheck.status).json({
        success: false,
        message: scheduleCheck.message,
      });
    }

    await connection.beginTransaction();
    const hasStatus = await workShiftHasStatus(connection);
    const activeShift = await findActiveShift(connection, employeeId);
    if (activeShift) {
      await connection.rollback();
      return res.status(409).json({
        success: false,
        message: 'Nhân viên đang trong ca làm',
        data: toShift(activeShift),
      });
    }

    const [result] = hasStatus
      ? await connection.execute(
          `INSERT INTO work_shifts (employee_id, shift_date, start_time, end_time, status)
           VALUES (?, CURDATE(), CURTIME(), NULL, 'working')`,
          [employeeId]
        )
      : await connection.execute(
          `INSERT INTO work_shifts (employee_id, shift_date, start_time, end_time)
           VALUES (?, CURDATE(), CURTIME(), NULL)`,
          [employeeId]
        );
    const [rows] = await connection.execute('SELECT * FROM work_shifts WHERE shift_id = ?', [
      result.insertId,
    ]);

    await connection.commit();
    res.status(201).json({
      success: true,
      message: 'Đã bắt đầu ca làm',
      data: toShift(rows[0]),
    });
  } catch (error) {
    console.error('work-shifts start failed:', error);
    await connection.rollback();
    res.status(500).json({ success: false, message: 'Lỗi bắt đầu ca làm', error: error.message });
  } finally {
    connection.release();
  }
});

router.post('/end', async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const employeeId = Number(req.body.employee_id);
    if (!employeeId) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập employee_id' });
    }

    await connection.beginTransaction();
    const hasStatus = await workShiftHasStatus(connection);
    const activeShift = await findActiveShift(connection, employeeId);
    if (!activeShift) {
      await connection.rollback();
      return res.status(404).json({ success: false, message: 'Nhân viên chưa có ca đang làm' });
    }

    if (hasStatus) {
      await connection.execute(
        `UPDATE work_shifts
         SET end_time = CURTIME(), status = 'completed'
         WHERE shift_id = ?`,
        [activeShift.shift_id]
      );
    } else {
      await connection.execute(
        `UPDATE work_shifts
         SET end_time = CURTIME()
         WHERE shift_id = ?`,
        [activeShift.shift_id]
      );
    }
    const [rows] = await connection.execute('SELECT * FROM work_shifts WHERE shift_id = ?', [
      activeShift.shift_id,
    ]);

    await connection.commit();
    res.json({
      success: true,
      message: 'Đã kết thúc ca làm',
      data: toShift(rows[0]),
    });
  } catch (error) {
    console.error('work-shifts end failed:', error);
    await connection.rollback();
    res.status(500).json({ success: false, message: 'Lỗi kết thúc ca làm', error: error.message });
  } finally {
    connection.release();
  }
});

module.exports = router;
