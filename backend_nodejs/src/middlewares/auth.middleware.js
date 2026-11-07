const jwt = require('jsonwebtoken');
const pool = require('../config/db');
const { secret } = require('../config/jwt');
const authenticated = Symbol('authenticated');

function normalizeRole(role) {
  const value = String(role || '').trim().toLowerCase();
  if (['admin', 'owner'].includes(value)) return 'admin';
  if (['employee', 'staff'].includes(value)) return 'employee';
  return value === 'customer' ? 'customer' : null;
}

function isOwner(user) { return normalizeRole(user?.role_name) === 'admin'; }
function isStaff(user) { return ['admin', 'employee'].includes(normalizeRole(user?.role_name)); }
function canAccessOrder(user, order) {
  return isStaff(user) || (normalizeRole(user?.role_name) === 'customer' && Number(order.customer_id) === Number(user.user_id));
}

async function requireAuth(req, res, next) {
  if (req[authenticated]) return next();
  const match = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization || '');
  if (!match) return res.status(401).json({ success: false, message: 'Vui lòng đăng nhập bằng JWT' });
  let payload;
  try {
    payload = jwt.verify(match[1], secret, { algorithms: ['HS256'] });
    // Password-reset JWTs are not access tokens, even with a valid signature.
    if (typeof payload !== 'object' || !Number.isFinite(payload.exp) ||
        (payload.purpose && payload.purpose !== 'access') ||
        !Number.isSafeInteger(Number(payload.id || payload.user_id)) || Number(payload.id || payload.user_id) <= 0) {
      throw new Error('Invalid access token');
    }
  } catch (_) {
    return res.status(401).json({ success: false, message: 'Token không hợp lệ hoặc đã hết hạn' });
  }
  try {
    const [users] = await pool.execute(
      `SELECT u.user_id, u.full_name, u.email, u.phone, u.address, u.points,
              u.membership_code, u.status, u.created_at, r.role_name
       FROM users u JOIN roles r ON r.role_id = u.role_id
       WHERE u.user_id = ? AND u.status = 'active' LIMIT 1`,
      [Number(payload.id || payload.user_id)],
    );
    const user = users[0];
    const role = normalizeRole(user?.role_name);
    if (!user || !role) return res.status(401).json({ success: false, message: 'Tài khoản không hợp lệ hoặc đã bị khóa' });
    req.user = { ...user, id: user.user_id, role_name: role };
    req[authenticated] = true;
    return next();
  } catch (_) {
    return res.status(503).json({ success: false, message: 'Chưa kiểm tra được phiên đăng nhập. Vui lòng thử lại.' });
  }
}

function requireRoles(...roles) {
  const allowed = roles.map(normalizeRole).filter(Boolean);
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ success: false, message: 'Vui lòng đăng nhập' });
    if (!allowed.includes(normalizeRole(req.user.role_name))) {
      return res.status(403).json({ success: false, message: 'Bạn không có quyền thực hiện thao tác này' });
    }
    return next();
  };
}

function requireSelfOrAdmin(getId) {
  return (req, res, next) => {
    const id = Number(getId(req));
    if (!Number.isSafeInteger(id) || id <= 0) return res.status(400).json({ success: false, message: 'Mã người dùng không hợp lệ' });
    if (!isOwner(req.user) && id !== Number(req.user?.user_id)) {
      return res.status(403).json({ success: false, message: 'Bạn chỉ được thao tác dữ liệu của mình' });
    }
    return next();
  };
}

module.exports = { requireAuth, requireRoles, requireSelfOrAdmin, normalizeRole, isOwner, isStaff, canAccessOrder };
