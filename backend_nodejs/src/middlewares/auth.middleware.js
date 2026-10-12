const jwt = require('jsonwebtoken');
const pool = require('../config/db');

async function loadUser(userId) {
  const [users] = await pool.execute(
    `SELECT u.user_id, u.full_name, u.email, u.phone, u.address, u.points,
            u.membership_code, u.status, u.created_at, r.role_name
     FROM users u
     JOIN roles r ON r.role_id = u.role_id
     WHERE u.user_id = ? AND u.status = 'active'
     LIMIT 1`,
    [userId]
  );
  const user = users[0] || null;
  if (user) {
    user.id = user.user_id;
  }
  return user;
}

async function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const [scheme, token] = authHeader.split(' ');
  const headerUserId = Number(req.get('x-user-id'));

  if (scheme === 'Bearer' && token) {
    try {
      const payload = jwt.verify(token, process.env.JWT_SECRET || 'mini_market_secret');
      const user = await loadUser(payload.id || payload.user_id);
      if (!user) {
        return res.status(401).json({ success: false, message: 'Tài khoản không hợp lệ' });
      }
      req.user = user;
      return next();
    } catch (error) {
      return res.status(401).json({ success: false, message: 'Token không hợp lệ hoặc đã hết hạn' });
    }
  }

  // Dev/backward-compatible fallback for old Flutter calls. Prefer Bearer token.
  if (headerUserId && process.env.ALLOW_HEADER_USER_AUTH !== 'false') {
    try {
      const user = await loadUser(headerUserId);
      if (!user) {
        return res.status(401).json({ success: false, message: 'Tài khoản không hợp lệ' });
      }
      req.user = user;
      return next();
    } catch (error) {
      return res.status(401).json({ success: false, message: 'Không kiểm tra được đăng nhập' });
    }
  }

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ success: false, message: 'Vui lòng đăng nhập' });
  }
}

function requireRoles(...roles) {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role_name)) {
      return res.status(403).json({ success: false, message: 'Bạn không có quyền thực hiện thao tác này' });
    }
    next();
  };
}

module.exports = { requireAuth, requireRoles };
