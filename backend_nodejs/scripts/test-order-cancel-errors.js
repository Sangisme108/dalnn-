const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

async function run(pool) {
  const routes = {};
  const router = Object.fromEntries(['get', 'post', 'put', 'patch', 'delete'].map((method) => [method, (route, ...handlers) => { routes[`${method} ${route}`] = handlers.at(-1); }]));
  const sandbox = {
    require: (name) => name === 'express' ? { Router: () => router }
      : name.includes('config/db') ? pool
      : name.includes('auth.middleware') ? { requireAuth: () => {}, requireRoles: () => () => {} } : {},
    module: { exports: {} }, console: { error: () => {} },
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../src/routes/order.routes.js'), 'utf8'), sandbox);
  let status;
  let payload;
  const res = { status: (value) => { status = value; return res; }, json: (body) => { payload = body; return res; } };
  await routes['put /:id/cancel']({ user: { id: 1 }, params: { id: '5' }, body: { reason: 'Mock reason' } }, res);
  return { status, payload };
}

(async () => {
  const lost = Object.assign(new Error('mock connection unavailable'), { code: 'ECONNREFUSED' });
  const connectionFailure = await run({ getConnection: async () => { throw lost; } });
  assert.equal(connectionFailure.status, 500);
  assert.equal(connectionFailure.payload.success, false);
  assert.equal(connectionFailure.payload.code, 'ECONNREFUSED');
  assert.match(connectionFailure.payload.message, /ECONNREFUSED/);
  let released = false;
  const sqlFailure = await run({ getConnection: async () => ({
    beginTransaction: async () => {},
    execute: async () => { throw Object.assign(new Error('mock SQL failure before any mutation'), { code: 'ER_LOCK_WAIT_TIMEOUT' }); },
    rollback: async () => { throw new Error('mock rollback failure'); },
    release: () => { released = true; },
  }) });
  assert.equal(sqlFailure.status, 500);
  assert.equal(sqlFailure.payload.code, 'ER_LOCK_WAIT_TIMEOUT');
  assert.equal(released, true);
  console.log('PASS: cancel connection/SQL/rollback failures return diagnostic JSON; no live database or orders used.');
})().catch((error) => { console.error(error); process.exitCode = 1; });
