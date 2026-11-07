const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const express = require('express');
const jwt = require('jsonwebtoken');

const src = path.resolve(__dirname, '../src');
const secret = 'authorization-test-key-not-used-outside-tests';
const users = new Map([
  [1, { user_id: 1, role_name: 'admin', status: 'active' }],
  [2, { user_id: 2, role_name: 'employee', status: 'active' }],
  [3, { user_id: 3, role_name: 'customer', status: 'active' }],
  [4, { user_id: 4, role_name: 'customer', status: 'active' }],
  [5, { user_id: 5, role_name: 'Owner', status: 'active' }],
  [6, { user_id: 6, role_name: 'staff', status: 'active' }],
  [7, { user_id: 7, role_name: 'admin', status: 'inactive' }],
]);
const orders = [
  { order_id: 10, customer_id: 3, employee_id: 2, status: 'pending', order_status: 'pending', payment_status: 'pending', final_amount: 100, order_type: 'online' },
  { order_id: 20, customer_id: 4, employee_id: 2, status: 'pending', order_status: 'pending', payment_status: 'pending', final_amount: 200, order_type: 'online' },
];
let calls = [];
let writes = [];
let databaseUnavailable = false;
const env = { NODE_ENV: 'test' };
const pool = {
  execute: async (sql, params = []) => {
    calls.push({ sql, params });
    if (databaseUnavailable) throw new Error('Mock database unavailable');
    if (sql.includes("u.status = 'active' LIMIT 1")) {
      const user = users.get(Number(params[0]));
      return [user?.status === 'active' ? [user] : []];
    }
    if (!/^\s*SELECT/i.test(sql)) {
      writes.push({ sql, params });
      return [{ affectedRows: 1, insertId: 99 }];
    }
    if (sql.includes('information_schema.COLUMNS')) return [[{ COLUMN_NAME: 'order_status' }, { COLUMN_NAME: 'transfer_content' }]];
    if (sql.includes('FROM order_items')) return [[{ product_id: 100, quantity: 1, price: 100, subtotal: 100, product_name: 'Mock product' }]];
    if (sql.includes('FROM orders') && sql.includes('WHERE o.order_id = ?')) return [orders.filter((o) => o.order_id === Number(params.at(-1)))];
    if (sql.includes('FROM orders') && sql.includes('WHERE order_id = ?')) return [orders.filter((o) => o.order_id === Number(params[0]))];
    if (sql.includes('SELECT o.customer_id')) return [orders.filter((o) => o.order_id === Number(params[1]))];
    if (sql.trim().startsWith('SELECT order_id') && sql.includes('FROM orders')) return [orders.filter((o) => o.order_id === Number(params.at(-1)))];
    if (sql.includes('FROM orders o')) return [sql.includes('o.customer_id = ?') ? orders.filter((o) => o.customer_id === Number(params[0])) : orders];
    if (sql.includes('FROM users u') && sql.includes('ORDER BY u.user_id')) {
      return [[...users.values()].filter((u) => !params.length || (sql.includes("r.role_name = 'customer'") && u.role_name === 'customer') || u.user_id === Number(params[0]))];
    }
    if (sql.includes('FROM inventory_items') && sql.includes('FOR UPDATE')) return [[{ inventory_item_id: 100, stock: 10 }]];
    return [[]];
  },
  getConnection: async () => ({
    execute: poolExecute,
    beginTransaction: async () => {}, commit: async () => {}, rollback: async () => {}, release: () => {},
  }),
};
function poolExecute(...args) { return pool.execute(...args); }

// Load the actual routers and middleware, replacing only DB/external services.
const cache = new Map();
function load(file) {
  const absolute = path.resolve(file);
  if (absolute === path.join(src, 'config/db.js')) return pool;
  if (absolute === path.join(src, 'config/jwt.js')) return { secret };
  if (cache.has(absolute)) return cache.get(absolute).exports;
  const module = { exports: {} };
  cache.set(absolute, module);
  const localRequire = createRequire(absolute);
  vm.runInNewContext(fs.readFileSync(absolute, 'utf8'), {
    require: (name) => name.startsWith('.') ? load(require.resolve(path.resolve(path.dirname(absolute), name))) : localRequire(name),
    module, exports: module.exports, __dirname: path.dirname(absolute), __filename: absolute,
    process: { env }, Buffer, URL, URLSearchParams, Promise, setTimeout, clearTimeout,
    console: { log: () => {}, warn: () => {}, error: () => {} },
    fetch: async () => { throw new Error('External APIs must not be called in authorization tests'); },
  }, { filename: absolute });
  return module.exports;
}

const app = express();
app.use(express.json());
const mounts = {
  '/api/products': 'product', '/api/categories': 'category', '/api/inventory': 'inventory',
  '/api/users': 'user', '/api/orders': 'order', '/orders': 'order', '/my-orders': 'myOrder',
  '/cart': 'cart', '/api/cart': 'cart', '/api/carts': 'cart', '/api/work-shifts': 'workShift',
  '/api/employee-schedules': 'employeeSchedule', '/api/points': 'point', '/api/reports': 'report',
  '/api/performance': 'performance', '/api/vouchers': 'voucher', '/api/ai': 'ai',
  '/api/payments': 'payment', '/api/webhook': 'payment', '/api/reviews': 'review',
  '/api/uploads': 'upload', '/api/auth': 'auth',
};
const cases = [];
for (const [mount, name] of Object.entries(mounts)) {
  const router = load(path.join(src, `routes/${name}.routes.js`));
  app.use(mount, router);
  for (const layer of router.stack) {
    if (!layer.route) continue;
    for (const method of Object.keys(layer.route.methods)) {
      const route = layer.route.path;
      const publicRoute = (['product', 'category'].includes(name) && method === 'get' && ['/', '/:id'].includes(route)) ||
        (name === 'review' && method === 'get') ||
        (name === 'payment' && ['/sepay', '/bank-webhook', '/vnpay-return', '/vnpay-ipn'].includes(route)) ||
        (name === 'auth' && route !== '/profile');
      if (!publicRoute) cases.push([method.toUpperCase(), mount + (route === '/' ? '' : route.replace(/:[A-Za-z]+/g, '10'))]);
    }
  }
}

let checks = 0;
let base;
const token = (id, overrides = {}, options = {}) => jwt.sign({ id, purpose: 'access', ...overrides }, secret, { expiresIn: '1h', ...options });
async function request(method, route, { id, bearer, headers = {}, body = {} } = {}) {
  const response = await fetch(base + route, {
    method,
    headers: { 'Content-Type': 'application/json', ...(bearer || id ? { Authorization: `Bearer ${bearer || token(id)}` } : {}), ...headers },
    ...(['GET', 'HEAD'].includes(method) ? {} : { body: JSON.stringify(body) }),
  });
  let payload;
  try { payload = await response.json(); } catch (_) { payload = {}; }
  return { status: response.status, payload };
}
async function expectStatus(method, route, expected, options) {
  const result = await request(method, route, options);
  assert.equal(result.status, expected, `${method} ${route}: ${JSON.stringify(result.payload)}`);
  checks++;
  return result.payload;
}

(async () => {
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
  try {
    for (const route of ['/api/products', '/api/categories', '/api/reviews/products/100']) await expectStatus('GET', route, 200);
    const expired = token(1, {}, { expiresIn: -1 });
    for (const [method, route] of cases) {
      const before = calls.length;
      await expectStatus(method, route, 401, { headers: { 'x-user-id': '1' } });
      await expectStatus(method, route, 401, { bearer: expired, headers: { 'x-user-id': '1' } });
      assert.equal(calls.length, before, 'Unauthenticated requests must not access DB');
    }
    for (const [method, route] of [
      ['POST', '/api/products'], ['PUT', '/api/products/100'], ['DELETE', '/api/products/100'],
      ['POST', '/api/categories'], ['GET', '/api/inventory/items'], ['POST', '/api/inventory/import'],
      ['POST', '/api/inventory/adjust'], ['POST', '/api/inventory/export'], ['POST', '/api/inventory/transfer-to-shelf'], ['POST','/api/inventory/valuation'], ['POST','/api/orders/10/refunds'], ['POST', '/api/uploads/product-image'],
      ['POST', '/api/users'], ['PUT', '/api/users/2'], ['DELETE', '/api/users/2'],
      ['GET', '/orders/pending'], ['GET', '/api/orders/online'], ['POST', '/api/orders'],
      ['PUT', '/orders/10/confirm'], ['PUT', '/orders/10/reject'], ['PATCH', '/api/orders/10/status'],
      ['GET', '/api/work-shifts'], ['POST', '/api/work-shifts/start'], ['POST', '/api/work-shifts/end'],
      ['GET', '/api/employee-schedules/overview/month'], ['PUT', '/api/employee-schedules/employee/2/day'],
      ['GET', '/api/reports/revenue'], ['GET', '/api/performance/dashboard'], ['GET', '/api/points/customer'],
      ['POST', '/api/points/add'], ['POST', '/api/vouchers'],
    ]) {
      const before = writes.length;
      await expectStatus(method, route, 403, { id: 3, headers: { 'x-user-id': '1' } });
      assert.equal(writes.length, before);
    }
    for (const [method, route] of [['POST','/api/inventory/valuation'], ['POST','/api/orders/10/refunds'], ['POST', '/api/users'], ['PUT', '/api/users/1'], ['DELETE', '/api/users/1'], ['GET', '/api/reports/revenue'], ['GET', '/api/performance/dashboard'], ['POST', '/api/vouchers'], ['PUT', '/api/employee-schedules/employee/2/day']]) {
      await expectStatus(method, route, 403, { id: 2, headers: { 'x-user-id': '1' } });
    }
    for (const id of [1, 2, 5, 6]) await expectStatus('GET', '/api/inventory/items', 200, { id });
    for(const id of [1,2,5,6]) await expectStatus('POST','/api/ai/cart-proposal',403,{id,body:{productId:1,quantity:1}});
    await expectStatus('POST','/api/ai/chat',400,{id:3,body:{message:'ok',confirmedCart:{productId:1,quantity:1}}});
    await expectStatus('POST','/api/ai/chat',403,{id:2,body:{message:'ok',confirmedCart:{productId:1,quantity:1}}});
    await expectStatus('GET','/api/users',401,{bearer:token(3,{purpose:'cart_confirmation'})});
    for (const id of [1, 2, 5, 6]) await expectStatus('POST', '/api/inventory/transfer-to-shelf', 400, { id, body: { quantity: 0 } });
    await expectStatus('POST', '/api/inventory/export', 400, { id: 2, body: { note: '@SHELF1:{"k":"fake"}' } });
    for (const id of [1, 5]) await expectStatus('GET', '/api/users', 200, { id });
    for (const [method, route] of [['GET', '/api/orders/20'], ['GET', '/api/orders/20/payment-status'], ['GET', '/api/orders/status/DH20'], ['GET', '/api/orders/history/4'], ['PUT', '/orders/20/cancel'], ['PUT', '/orders/20/received'], ['POST', '/api/payments/vnpay/create'], ['PUT', '/api/users/4/profile'], ['GET', '/api/vouchers/user/4'], ['GET', '/api/carts/4'], ['PUT', '/api/carts/4']]) {
      const before = writes.length;
      await expectStatus(method, route, 403, { id: 3, headers: { 'x-user-id': '4' }, body: { order_id: 20, reason: 'Mock', full_name: 'Mock' } });
      assert.equal(writes.length, before, 'Cross-customer access must not write');
    }
    for (const route of ['/api/orders/10', '/api/orders/10/payment-status', '/api/orders/status/DH10']) await expectStatus('GET', route, 200, { id: 3, headers: { 'x-user-id': '4' } });
    const own = await expectStatus('GET', '/api/orders', 200, { id: 3 });
    assert.deepEqual(own.data.map((o) => o.id), ['10']);
    const mine = await expectStatus('GET', '/my-orders', 200, { id: 3, headers: { 'x-user-id': '4' } });
    assert.deepEqual(mine.data.map((o) => o.id), ['10']);
    for (const id of [1, 2]) await expectStatus('GET', '/api/orders/20', 200, { id });
    for (const route of ['/api/users/1/employee-summary', '/api/work-shifts/employee/1', '/api/employee-schedules/employee/1/month', '/api/work-shifts?employee_id=1']) await expectStatus('GET', route, 403, { id: 2 });
    await expectStatus('POST', '/api/work-shifts/start', 403, { id: 2, body: { employee_id: 1 } });
    await expectStatus('POST', '/api/work-shifts/end', 403, { id: 2, body: { employee_id: 1 } });
    await expectStatus('GET', '/api/work-shifts', 200, { id: 2 });
    assert(calls.some((c) => c.sql.includes('FROM work_shifts ws') && c.params.includes(2)));
    await expectStatus('POST', '/api/inventory/import', 200, { id: 2, body: { inventory_item_id: 100, employee_id: 1, quantity: 1, import_price: 50 } });
    assert.equal(writes.find((c) => c.sql.includes('INSERT INTO inventory_logs')).params[1], 2, 'Audit actor comes from JWT');
    for (const bearer of ['invalid', jwt.sign({ id: 1 }, 'wrong-key', { expiresIn: '1h' }), token(3, { purpose: 'password_reset' }), jwt.sign({ id: 1 }, secret), token(7), token(999), token(3, { role_name: 'admin' }, { algorithm: 'HS384' })]) {
      await expectStatus('GET', '/api/users', 401, { bearer });
    }
    await expectStatus('POST', '/api/products', 403, { bearer: token(3, { role_name: 'admin' }) });
    for(let i=0;i<30;i++) await expectStatus('POST','/api/ai/reply',200,{id:3,body:{message:'Chào'}});
    await expectStatus('POST','/api/ai/reply',429,{id:3,body:{message:'Chào'}});
    await expectStatus('POST','/api/ai/chat',400,{id:3,body:{message:'ok',confirmedCart:{productId:1,quantity:1}}});
    databaseUnavailable = true;
    await expectStatus('GET', '/api/users', 503, { id: 1 });
    databaseUnavailable = false;
    const before = writes.length;
    await expectStatus('POST', '/api/payments/sepay', 503);
    env.BANK_WEBHOOK_SECRET = 'webhook-test-only';
    await expectStatus('POST', '/api/payments/sepay', 401);
    await expectStatus('POST', '/api/webhook/sepay', 401, { headers: { Authorization: 'Apikey incorrect' } });
    await expectStatus('POST', '/api/payments/bank-webhook', 400, { headers: { Authorization: 'Apikey webhook-test-only' } });
    assert.equal(writes.length, before);
    await expectStatus('POST', '/api/payments/bank-transfer/manual-confirm', 404);
    env.VNP_TMN_CODE = 'TEST_MERCHANT';
    env.VNP_HASH_SECRET = 'private-test-signing-key';
    const vnpay = load(path.join(src, 'services/vnpay.service.js'));
    const signed = vnpay.createPaymentUrl({ orderId: 10, amount: 100, orderInfo: 'Mock', txnRef: '10_test', ipAddr: '127.0.0.1' });
    const query = new URL(signed.paymentUrl).searchParams;
    query.set('vnp_Amount', '1');
    const beforeIpn = calls.length;
    const invalidIpn = await expectStatus('GET', `/api/payments/vnpay-ipn?${query}`, 200);
    assert.equal(invalidIpn.RspCode, '97');
    assert.equal(calls.length, beforeIpn, 'Invalid VNPay signatures must not access DB');
    console.log(`PASS: ${checks} HTTP authorization checks across ${cases.length} protected routes/aliases. Real JWT/Express middleware; mocked DB; no live database, payments, SMS or AI calls.`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
