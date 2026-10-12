const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'mini_market_secret';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';
const RESET_TOKEN_EXPIRES_IN = process.env.RESET_TOKEN_EXPIRES_IN || '15m';
const BCRYPT_ROUNDS = Number(process.env.BCRYPT_ROUNDS || 10);

function isBcryptHash(value) {
  return typeof value === 'string' && /^\$2[aby]\$\d{2}\$/.test(value);
}

async function hashPassword(password) {
  return bcrypt.hash(password, BCRYPT_ROUNDS);
}

async function verifyPassword(password, storedValue) {
  if (!storedValue) return false;
  if (isBcryptHash(storedValue)) {
    return bcrypt.compare(password, storedValue);
  }
  return password === storedValue;
}

function signAuthToken(user) {
  return jwt.sign(
    {
      id: user.user_id,
      user_id: user.user_id,
      email: user.email,
      role_name: user.role_name,
    },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRES_IN }
  );
}

function signResetToken(resetToken) {
  return jwt.sign(
    {
      purpose: 'password_reset',
      token_id: resetToken.id,
      user_id: resetToken.user_id,
      type: resetToken.type,
    },
    JWT_SECRET,
    { expiresIn: RESET_TOKEN_EXPIRES_IN }
  );
}

function verifyResetToken(token) {
  const payload = jwt.verify(token, JWT_SECRET);
  if (payload.purpose !== 'password_reset') {
    throw new Error('Token đặt lại mật khẩu không hợp lệ');
  }
  return payload;
}

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function normalizePhone(phone) {
  return String(phone || '').replace(/\D/g, '');
}

function toInternationalPhone(phone) {
  const raw = String(phone || '').trim();
  if (raw.startsWith('+')) return raw.replace(/[^\d+]/g, '');

  const digits = normalizePhone(raw);
  if (!digits) return '';
  if (digits.startsWith('84')) return `+${digits}`;
  if (digits.startsWith('0')) return `+84${digits.slice(1)}`;
  return `+${digits}`;
}

function normalizeIdentifier(identifier) {
  const value = String(identifier || '').trim();
  return value.includes('@') ? normalizeEmail(value) : normalizePhone(value);
}

function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

module.exports = {
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
};
