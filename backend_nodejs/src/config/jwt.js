const { randomBytes } = require('node:crypto');

const configuredSecret = process.env.JWT_SECRET;
if (!configuredSecret && process.env.NODE_ENV === 'production') {
  throw new Error('JWT_SECRET must be configured in production');
}
// A development restart invalidates sessions unless JWT_SECRET is configured.
const secret = configuredSecret || randomBytes(48).toString('hex');
if (!configuredSecret) {
  console.warn('JWT_SECRET is not configured: using a temporary development key. Sign in again after restarting the backend.');
}

module.exports = { secret };
