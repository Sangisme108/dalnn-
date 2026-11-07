const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const routes = new Map();
const router = Object.fromEntries(['get', 'post', 'put', 'patch', 'delete'].map((method) => [method, (route, ...handlers) => routes.set(`${method} ${route}`, handlers)]));
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../src/routes/payment.routes.js'), 'utf8'), {
  require: (name) => name === 'express' ? { Router: () => router }
    : name.includes('auth.middleware') ? { requireAuth: () => {} } : {},
  module: { exports: {} }, process: { env: {} },
});
assert.equal(routes.has('post /bank-transfer/manual-confirm'), false);
assert.equal(routes.has('post /sepay'), true);
assert.equal(routes.has('post /bank-webhook'), true);
assert.equal(routes.get('post /sepay').at(-1), routes.get('post /bank-webhook').at(-1));
assert.equal(routes.has('post /vnpay/create'), true);
assert.equal(routes.has('get /vnpay-ipn'), true);
assert.equal(routes.has('get /vnpay-return'), true);
console.log('PASS: manual bank confirmation removed; SePay/bank webhook and VNPay routes preserved. No live database or payment calls.');
