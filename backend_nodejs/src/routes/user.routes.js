const express = require('express');
const pool = require('../config/db');
const { hashPassword } = require('../services/auth.service');
const { requireAuth, requireRoles } = require('../middlewares/auth.middleware');

const router = express.Router();

function toUser(row) {
  return {
    user_id: row.user_id,
    id: String(row.user_id),
    full_name: row.full_name,
    fullName: row.full_name,
    email: row.email,
    phone: row.phone,
    address: row.address,
    role_id: row.role_id,
    role_name: row.role_name,
    role: row.role_name,
    points: row.points,
    membership_code: row.membership_code,
    status: row.status,
    created_at: row.created_at,
  };
}

function toEmployeePayment(row) {
  return {
    order_id: row.order_id,
    total_amount: Number(row.total_amount || 0),
    final_amount: Number(row.final_amount || row.amount || 0),
    method: row.method,
    payment_status: row.payment_status || row.status,
    paid_at: row.paid_at,
  };
}

function toNumber(value) {
  return Number(value || 0);
}

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
    shift_date: formatDateOnly(row.shift_date),
    start_time: formatTimeOnly(row.start_time),
    end_time: formatTimeOnly(row.end_time),
    status: row.status || (row.end_time ? 'closed' : 'active'),
    note: row.note,
  };
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

function emptyEmployeeSummary(user) {
  return {
    user: toUser(user),
    account_status: user.status,
    current_shift: null,
    latest_shift: null,
    summary_scope: 'none',
    work_status: 'off',
    last_work_date: null,
    start_time: null,
    end_time: null,
    total_orders: 0,
    paid_orders_count: 0,
    total_revenue: 0,
    average_revenue_per_order: 0,
    total_points_added: 0,
    payment_history: [],
    payments: [],
  };
}

router.get('/', async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT u.*, r.role_name
       FROM users u
       JOIN roles r ON r.role_id = u.role_id
       ORDER BY u.user_id DESC`
    );
    res.json({ success: true, data: rows.map(toUser) });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi lấy người dùng', error: error.message });
  }
});

router.post('/', requireAuth, requireRoles('admin'), async (req, res) => {
  try {
    const { full_name, fullName, email, phone, password, address, role_name, role } = req.body;
    const name = full_name || fullName;
    const roleName = role_name || role || 'employee';

    if (!name || !email || !password) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập full_name, email, password' });
    }

    const [existing] = await pool.execute(
      `SELECT user_id, email, phone
       FROM users
       WHERE email = ? OR (? IS NOT NULL AND phone = ?)
       LIMIT 1`,
      [email, phone || null, phone || null]
    );
    if (existing.length > 0) {
      const duplicatedField = existing[0].email === email ? 'Email' : 'Số điện thoại';
      return res.status(409).json({ success: false, message: `${duplicatedField} đã tồn tại` });
    }

    const [roles] = await pool.execute('SELECT role_id FROM roles WHERE role_name = ?', [roleName]);
    if (roles.length === 0) {
      return res.status(400).json({ success: false, message: 'Role không hợp lệ' });
    }

    const passwordHash = await hashPassword(password);
    const hasPasswordHash = await columnExists('users', 'password_hash');
    let result;
    if (hasPasswordHash) {
      [result] = await pool.execute(
        `INSERT INTO users (full_name, email, phone, password, password_hash, address, role_id)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [name, email, phone || null, passwordHash, passwordHash, address || null, roles[0].role_id]
      );
    } else {
      [result] = await pool.execute(
        `INSERT INTO users (full_name, email, phone, password, address, role_id)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [name, email, phone || null, passwordHash, address || null, roles[0].role_id]
      );
    }
    const [rows] = await pool.execute(
      `SELECT u.*, r.role_name FROM users u JOIN roles r ON r.role_id = u.role_id WHERE u.user_id = ?`,
      [result.insertId]
    );
    res.status(201).json({ success: true, message: 'Đã thêm người dùng', data: toUser(rows[0]) });
  } catch (error) {
    const status = error.code === 'ER_DUP_ENTRY' ? 409 : 500;
    res.status(status).json({ success: false, message: 'Lỗi thêm người dùng', error: error.message });
  }
});

router.get('/:id/employee-summary', async (req, res) => {
  try {
    const [users] = await pool.execute(
      `SELECT u.*, r.role_name
       FROM users u
       JOIN roles r ON r.role_id = u.role_id
       WHERE u.user_id = ? AND r.role_name IN ('employee', 'admin')`,
      [req.params.id]
    );
    if (users.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy nhân viên' });
    }

    const hasShiftStatus = await columnExists('work_shifts', 'status');
    const hasOrdersShiftId = await columnExists('orders', 'shift_id');
    const currentShiftWhere = hasShiftStatus
      ? "end_time IS NULL AND status IN ('active', 'working', 'open')"
      : 'end_time IS NULL';

    let currentShift = null;
    let latestShift = null;
    try {
      const [currentShiftRows] = await pool.execute(
        `SELECT *
         FROM work_shifts
         WHERE employee_id = ?
           AND ${currentShiftWhere}
         ORDER BY shift_date DESC, start_time DESC, shift_id DESC
         LIMIT 1`,
        [req.params.id]
      );

      const [latestShiftRows] = await pool.execute(
        `SELECT *
         FROM work_shifts
         WHERE employee_id = ?
         ORDER BY shift_date DESC, start_time DESC, shift_id DESC
         LIMIT 1`,
        [req.params.id]
      );
      currentShift = currentShiftRows[0] || null;
      latestShift = latestShiftRows[0] || null;
    } catch (shiftError) {
      console.error('employee-summary shift query failed:', shiftError);
    }

    const statsShift = currentShift || latestShift;
    const statsParams = [req.params.id];
    let statsWhere = 'o.employee_id = ?';
    if (statsShift && hasOrdersShiftId) {
      statsWhere += ' AND o.shift_id = ?';
      statsParams.push(statsShift.shift_id);
    }

    let [summaryRows] = await pool.execute(
      `SELECT
         COUNT(DISTINCT o.order_id) AS total_orders,
         COALESCE(SUM(p.amount), 0) AS total_revenue,
         COALESCE(SUM(lt.points_added), 0) AS total_points_added
       FROM orders o
       JOIN payments p ON p.order_id = o.order_id
       LEFT JOIN (
         SELECT order_id, SUM(CASE WHEN points_change > 0 THEN points_change ELSE 0 END) AS points_added
         FROM loyalty_transactions
         GROUP BY order_id
       ) lt ON lt.order_id = o.order_id
       WHERE ${statsWhere}
         AND p.status IN ('paid', 'success')
         AND o.payment_status IN ('paid', 'success')`,
      statsParams
    );

    let summaryScope = statsShift && hasOrdersShiftId ? 'shift' : 'employee_total';
    let summary = summaryRows[0] || {};
    if (statsShift && hasOrdersShiftId && toNumber(summary.total_orders) === 0) {
      [summaryRows] = await pool.execute(
        `SELECT
           COUNT(DISTINCT o.order_id) AS total_orders,
           COALESCE(SUM(p.amount), 0) AS total_revenue,
           COALESCE(SUM(lt.points_added), 0) AS total_points_added
         FROM orders o
         JOIN payments p ON p.order_id = o.order_id
         LEFT JOIN (
           SELECT order_id, SUM(CASE WHEN points_change > 0 THEN points_change ELSE 0 END) AS points_added
           FROM loyalty_transactions
           GROUP BY order_id
         ) lt ON lt.order_id = o.order_id
         WHERE o.employee_id = ?
           AND p.status IN ('paid', 'success')
           AND o.payment_status IN ('paid', 'success')`,
        [req.params.id]
      );
      summary = summaryRows[0] || {};
      summaryScope = 'employee_total_fallback';
    }

    const historyParams = [req.params.id];
    let historyWhere = 'o.employee_id = ?';
    if (statsShift && hasOrdersShiftId && summaryScope === 'shift') {
      historyWhere += ' AND o.shift_id = ?';
      historyParams.push(statsShift.shift_id);
    }

    const [payments] = await pool.execute(
      `SELECT o.order_id, ${hasOrdersShiftId ? 'o.shift_id' : 'NULL AS shift_id'}, o.total_amount, o.final_amount, o.payment_status,
              p.method, p.amount, p.status, p.paid_at
       FROM orders o
       JOIN payments p ON p.order_id = o.order_id
       WHERE ${historyWhere}
         AND p.status IN ('paid', 'success')
         AND o.payment_status IN ('paid', 'success')
       ORDER BY p.paid_at DESC, p.payment_id DESC
       LIMIT 50`,
      historyParams
    );

    const totalOrders = toNumber(summary.total_orders);
    const totalRevenue = toNumber(summary.total_revenue);

    res.json({
      success: true,
      data: {
        user: toUser(users[0]),
        account_status: users[0].status,
        current_shift: toShift(currentShift),
        latest_shift: toShift(latestShift),
        summary_scope: summaryScope,
        work_status: currentShift ? 'working' : 'off',
        last_work_date: latestShift ? formatDateOnly(latestShift.shift_date) : null,
        start_time: statsShift ? formatTimeOnly(statsShift.start_time) : null,
        end_time: currentShift ? null : (statsShift ? formatTimeOnly(statsShift.end_time) : null),
        total_orders: totalOrders,
        paid_orders_count: totalOrders,
        total_revenue: totalRevenue,
        average_revenue_per_order: totalOrders > 0 ? totalRevenue / totalOrders : 0,
        total_points_added: toNumber(summary.total_points_added),
        payment_history: payments.map(toEmployeePayment),
        payments: payments.map(toEmployeePayment),
      },
    });
  } catch (error) {
    console.error('employee-summary failed:', error);
    res.status(500).json({ success: false, message: 'Lỗi lấy chi tiết nhân viên', error: error.message });
  }
});

router.put('/:id/profile', requireAuth, async (req, res) => {
  try {
    const { full_name, fullName, phone, password, address } = req.body;
    const name = full_name || fullName || null;
    const isOwner = Number(req.user?.id || req.user?.user_id) === Number(req.params.id);
    const isAdmin = req.user?.role_name === 'admin';

    if (!isOwner && !isAdmin) {
      return res.status(403).json({ success: false, message: 'Bạn không có quyền cập nhật tài khoản này' });
    }

    if (!name && phone === undefined && address === undefined && !password) {
      return res.status(400).json({ success: false, message: 'Không có thông tin cần cập nhật' });
    }

    if (phone) {
      const [existing] = await pool.execute(
        'SELECT user_id FROM users WHERE phone = ? AND user_id <> ? LIMIT 1',
        [phone, req.params.id]
      );
      if (existing.length > 0) {
        return res.status(409).json({ success: false, message: 'Số điện thoại đã tồn tại' });
      }
    }

    const passwordHash = password ? await hashPassword(password) : null;
    const hasPasswordHash = await columnExists('users', 'password_hash');
    if (hasPasswordHash) {
      await pool.execute(
        `UPDATE users
         SET full_name = COALESCE(?, full_name),
             phone = ?,
             password = COALESCE(?, password),
             password_hash = COALESCE(?, password_hash),
             address = ?
         WHERE user_id = ?`,
        [name, phone ?? null, passwordHash, passwordHash, address ?? null, req.params.id]
      );
    } else {
      await pool.execute(
        `UPDATE users
         SET full_name = COALESCE(?, full_name),
             phone = ?,
             password = COALESCE(?, password),
             address = ?
         WHERE user_id = ?`,
        [name, phone ?? null, passwordHash, address ?? null, req.params.id]
      );
    }

    const [rows] = await pool.execute(
      `SELECT u.*, r.role_name FROM users u JOIN roles r ON r.role_id = u.role_id WHERE u.user_id = ?`,
      [req.params.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy người dùng' });
    }
    res.json({ success: true, message: 'Đã cập nhật thông tin cá nhân', data: toUser(rows[0]) });
  } catch (error) {
    const status = error.code === 'ER_DUP_ENTRY' ? 409 : 500;
    res.status(status).json({ success: false, message: 'Lỗi cập nhật thông tin cá nhân', error: error.message });
  }
});

router.put('/:id', requireAuth, requireRoles('admin'), async (req, res) => {
  try {
    const { full_name, fullName, email, phone, password, address, role_name, role, status } = req.body;
    let roleId = null;
    if (role_name || role) {
      const [roles] = await pool.execute('SELECT role_id FROM roles WHERE role_name = ?', [role_name || role]);
      if (roles.length === 0) {
        return res.status(400).json({ success: false, message: 'Role không hợp lệ' });
      }
      roleId = roles[0].role_id;
    }

    const passwordHash = password ? await hashPassword(password) : null;
    const hasPasswordHash = await columnExists('users', 'password_hash');
    if (hasPasswordHash) {
      await pool.execute(
        `UPDATE users
         SET full_name = COALESCE(?, full_name),
             email = COALESCE(?, email),
             phone = ?,
             password = COALESCE(?, password),
             password_hash = COALESCE(?, password_hash),
             address = ?,
             role_id = COALESCE(?, role_id),
             status = COALESCE(?, status)
         WHERE user_id = ?`,
        [
          full_name || fullName || null,
          email || null,
          phone ?? null,
          passwordHash,
          passwordHash,
          address ?? null,
          roleId,
          status || null,
          req.params.id,
        ]
      );
    } else {
      await pool.execute(
        `UPDATE users
         SET full_name = COALESCE(?, full_name),
             email = COALESCE(?, email),
             phone = ?,
             password = COALESCE(?, password),
             address = ?,
             role_id = COALESCE(?, role_id),
             status = COALESCE(?, status)
         WHERE user_id = ?`,
        [
          full_name || fullName || null,
          email || null,
          phone ?? null,
          passwordHash,
          address ?? null,
          roleId,
          status || null,
          req.params.id,
        ]
      );
    }

    const [rows] = await pool.execute(
      `SELECT u.*, r.role_name FROM users u JOIN roles r ON r.role_id = u.role_id WHERE u.user_id = ?`,
      [req.params.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy người dùng' });
    }
    res.json({ success: true, message: 'Đã cập nhật người dùng', data: toUser(rows[0]) });
  } catch (error) {
    const status = error.code === 'ER_DUP_ENTRY' ? 409 : 500;
    res.status(status).json({ success: false, message: 'Lỗi cập nhật người dùng', error: error.message });
  }
});

router.delete('/:id', requireAuth, requireRoles('admin'), async (req, res) => {
  try {
    await pool.execute("UPDATE users SET status = 'inactive' WHERE user_id = ?", [req.params.id]);
    res.json({ success: true, message: 'Đã khóa người dùng' });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi xóa người dùng', error: error.message });
  }
});

module.exports = router;
