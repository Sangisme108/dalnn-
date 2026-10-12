const express = require('express');
const bcrypt = require('bcrypt');
const pool = require('../config/db');
const { requireAuth } = require('../middlewares/auth.middleware');
const {
  hashPassword,
  verifyPassword,
  isBcryptHash,
  signAuthToken,
  signResetToken,
  verifyResetToken,
  normalizeEmail,
  normalizePhone,
  toInternationalPhone,
  normalizeIdentifier,
  generateOtp,
} = require('../services/auth.service');
const {
  sendPasswordResetEmail,
  sendPasswordResetSms,
} = require('../services/otp.service');

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

async function findRoleId(roleName) {
  const [roles] = await pool.execute(
    'SELECT role_id FROM roles WHERE role_name = ? LIMIT 1',
    [roleName]
  );
  return roles[0]?.role_id || null;
}

async function findActiveUserByIdentifier(identifier, onlyCustomer = false) {
  const normalized = normalizeIdentifier(identifier);
  const where = normalized.includes('@')
    ? 'LOWER(u.email) = ?'
    : "REPLACE(REPLACE(REPLACE(REPLACE(u.phone, ' ', ''), '-', ''), '.', ''), '+', '') = ?";
  const roleFilter = onlyCustomer ? "AND r.role_name = 'customer'" : '';

  const [users] = await pool.execute(
    `SELECT u.*, r.role_name
     FROM users u
     JOIN roles r ON r.role_id = u.role_id
     WHERE ${where}
       AND u.status = 'active'
       ${roleFilter}
     LIMIT 1`,
    [normalized]
  );
  return users[0] || null;
}

async function updatePasswordHash(userId, passwordHash) {
  const hasPasswordHash = await columnExists('users', 'password_hash');
  if (hasPasswordHash) {
    await pool.execute(
      'UPDATE users SET password = ?, password_hash = ? WHERE user_id = ?',
      [passwordHash, passwordHash, userId]
    );
    return;
  }
  await pool.execute('UPDATE users SET password = ? WHERE user_id = ?', [
    passwordHash,
    userId,
  ]);
}

async function insertUser({ fullName, email, phone, passwordHash, address, roleId }) {
  const hasPasswordHash = await columnExists('users', 'password_hash');
  if (hasPasswordHash) {
    return pool.execute(
      `INSERT INTO users
       (full_name, email, phone, password, password_hash, address, role_id)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [fullName, email, phone || null, passwordHash, passwordHash, address || null, roleId]
    );
  }

  return pool.execute(
    `INSERT INTO users
     (full_name, email, phone, password, address, role_id)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [fullName, email, phone || null, passwordHash, address || null, roleId]
  );
}

async function createResetOtp(user, type) {
  const otp = generateOtp();
  const otpHash = await bcrypt.hash(otp, 10);
  const expiredAt = new Date(Date.now() + 10 * 60 * 1000);

  await pool.execute(
    `INSERT INTO password_reset_tokens
     (user_id, otp_code, type, expired_at, used)
     VALUES (?, ?, ?, ?, 0)`,
    [user.user_id, otpHash, type, expiredAt]
  );

  return { otp, expiredAt };
}

// Customer self registration only. Employees are created by admin; admin accounts are seeded.
router.post('/register', async (req, res) => {
  try {
    const fullName = String(req.body.full_name || req.body.fullName || '').trim();
    const email = normalizeEmail(req.body.email);
    const phone = normalizePhone(req.body.phone);
    const password = String(req.body.password || '');
    const address = String(req.body.address || '').trim();

    if (!fullName || !email || !phone || !password) {
      return res.status(400).json({
        success: false,
        message: 'Vui lòng nhập họ tên, email, số điện thoại và mật khẩu',
      });
    }

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return res.status(400).json({ success: false, message: 'Email không đúng định dạng' });
    }

    if (phone.length < 8 || phone.length > 15) {
      return res.status(400).json({ success: false, message: 'Số điện thoại không hợp lệ' });
    }

    if (password.length < 6) {
      return res.status(400).json({ success: false, message: 'Mật khẩu phải có ít nhất 6 ký tự' });
    }

    const [existing] = await pool.execute(
      `SELECT user_id, email, phone
       FROM users
       WHERE LOWER(email) = ? OR phone = ?
       LIMIT 1`,
      [email, phone]
    );
    if (existing.length > 0) {
      const duplicatedField = existing[0].email?.toLowerCase() === email ? 'Email' : 'Số điện thoại';
      return res.status(409).json({ success: false, message: `${duplicatedField} đã tồn tại` });
    }

    const roleId = await findRoleId('customer');
    if (!roleId) {
      return res.status(500).json({
        success: false,
        message: "Chưa có role 'customer' trong database",
      });
    }

    const passwordHash = await hashPassword(password);
    await insertUser({ fullName, email, phone, passwordHash, address, roleId });

    res.status(201).json({
      success: true,
      message: 'Đăng ký khách hàng thành công',
    });
  } catch (error) {
    const status = error.code === 'ER_DUP_ENTRY' ? 409 : 500;
    res.status(status).json({
      success: false,
      message: 'Lỗi đăng ký',
      error: error.message,
    });
  }
});

router.post('/login', async (req, res) => {
  try {
    const identifier = req.body.identifier || req.body.email || req.body.phone;
    const password = String(req.body.password || '');

    if (!identifier || !password) {
      return res.status(400).json({
        success: false,
        message: 'Vui lòng nhập email/số điện thoại và mật khẩu',
      });
    }

    const user = await findActiveUserByIdentifier(identifier);
    const storedPassword = user?.password_hash || user?.password;
    const passwordOk = user ? await verifyPassword(password, storedPassword) : false;

    if (!user || !passwordOk) {
      return res.status(401).json({
        success: false,
        message: 'Sai email/số điện thoại hoặc mật khẩu',
      });
    }

    if (!isBcryptHash(storedPassword)) {
      await updatePasswordHash(user.user_id, await hashPassword(password));
    }

    const safeUser = toUser(user);
    res.json({
      success: true,
      message: 'Đăng nhập thành công',
      token: signAuthToken(safeUser),
      user: safeUser,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Lỗi đăng nhập',
      error: error.message,
    });
  }
});

router.post('/forgot-password/email', async (req, res) => {
  try {
    const email = normalizeEmail(req.body.email || req.body.identifier);
    if (!email) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập email' });
    }

    const user = await findActiveUserByIdentifier(email, true);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy tài khoản khách hàng' });
    }

    const { otp } = await createResetOtp(user, 'EMAIL');
    const delivery = await sendPasswordResetEmail(user.email, otp);

    res.json({
      success: true,
      message: delivery.sent
        ? 'Đã gửi mã OTP về Gmail'
        : 'Đã tạo mã OTP. Kiểm tra console backend để demo',
      ...(delivery.sent || process.env.NODE_ENV === 'production' ? {} : { demo_otp: otp }),
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi gửi OTP Gmail', error: error.message });
  }
});

router.post('/forgot-password/phone', async (req, res) => {
  try {
    const phone = normalizePhone(req.body.phone || req.body.identifier);
    if (!phone) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập số điện thoại' });
    }

    const user = await findActiveUserByIdentifier(phone, true);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy tài khoản khách hàng' });
    }

    const { otp } = await createResetOtp(user, 'PHONE');
    const delivery = await sendPasswordResetSms(toInternationalPhone(user.phone), otp);

    res.json({
      success: true,
      message: delivery.sent
        ? 'Đã gửi mã OTP về số điện thoại'
        : 'Đã tạo mã OTP. Kiểm tra console backend để demo SMS',
      ...(delivery.sent || process.env.NODE_ENV === 'production' ? {} : { demo_otp: otp }),
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi tạo OTP số điện thoại', error: error.message });
  }
});

router.post('/verify-otp', async (req, res) => {
  try {
    const identifier = req.body.identifier || req.body.email || req.body.phone;
    const otp = String(req.body.otp || req.body.otp_code || '').trim();
    const type = String(req.body.type || '').trim().toUpperCase();

    if (!identifier || !otp || !['EMAIL', 'PHONE'].includes(type)) {
      return res.status(400).json({
        success: false,
        message: 'Vui lòng nhập phương thức, tài khoản và OTP',
      });
    }

    const user = await findActiveUserByIdentifier(identifier, true);
    if (!user) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy tài khoản khách hàng' });
    }

    const [tokens] = await pool.execute(
      `SELECT *
       FROM password_reset_tokens
       WHERE user_id = ?
         AND type = ?
         AND used = 0
         AND expired_at > NOW()
       ORDER BY created_at DESC, id DESC
       LIMIT 1`,
      [user.user_id, type]
    );

    const tokenRow = tokens[0];
    const otpOk = tokenRow ? await bcrypt.compare(otp, tokenRow.otp_code) : false;
    if (!tokenRow || !otpOk) {
      return res.status(400).json({ success: false, message: 'OTP không đúng hoặc đã hết hạn' });
    }

    res.json({
      success: true,
      message: 'Xác thực OTP thành công',
      reset_token: signResetToken({
        id: tokenRow.id,
        user_id: user.user_id,
        type,
      }),
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi xác thực OTP', error: error.message });
  }
});

router.post('/reset-password', async (req, res) => {
  try {
    const resetToken = String(req.body.reset_token || '').trim();
    const newPassword = String(req.body.new_password || req.body.password || '');

    if (!resetToken || !newPassword) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập token và mật khẩu mới' });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({ success: false, message: 'Mật khẩu mới phải có ít nhất 6 ký tự' });
    }

    const payload = verifyResetToken(resetToken);
    const [tokens] = await pool.execute(
      `SELECT *
       FROM password_reset_tokens
       WHERE id = ?
         AND user_id = ?
         AND used = 0
         AND expired_at > NOW()
       LIMIT 1`,
      [payload.token_id, payload.user_id]
    );

    if (tokens.length === 0) {
      return res.status(400).json({ success: false, message: 'Token đặt lại mật khẩu không hợp lệ hoặc đã hết hạn' });
    }

    await updatePasswordHash(payload.user_id, await hashPassword(newPassword));
    await pool.execute('UPDATE password_reset_tokens SET used = 1 WHERE id = ?', [payload.token_id]);

    res.json({ success: true, message: 'Đặt lại mật khẩu thành công' });
  } catch (error) {
    res.status(400).json({ success: false, message: 'Lỗi đặt lại mật khẩu', error: error.message });
  }
});

router.get('/profile', requireAuth, async (req, res) => {
  res.json({ success: true, data: toUser(req.user) });
});

module.exports = router;
