const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

async function run(rows, { legacy = false, fail = false } = {}) {
  const calls = [];
  let handler;
  const router = Object.fromEntries(['get', 'post', 'put', 'patch', 'delete'].map((method) => [method, (route, ...handlers) => {
    if (method === 'get' && route === '/pending') handler = handlers.at(-1);
  }]));
  router.use = () => {};
  const pool = {
    execute: async (sql, params) => {
      calls.push({ sql, params });
      if (fail) throw new Error('Database unavailable');
      if (sql.includes('information_schema')) return [legacy ? [] : [{ COLUMN_NAME: 'order_status' }]];
      if (sql.includes('FROM orders o')) return [rows];
      assert.match(sql, /oi.order_id IN/);
      assert.equal((sql.match(/\?/g) || []).length, params.length);
      return [params.filter((id) => Number(id) % 2).map((id) => ({ order_id: id, product_id: 10, product_name: 'Product', quantity: 2, price: '35000', subtotal: '70000' }))];
    },
    getConnection: () => { throw new Error('Must not reserve a connection'); },
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../src/routes/order.routes.js'), 'utf8'), {
    require: (name) => name === 'express' ? { Router: () => router }
      : name.includes('config/db') ? pool
      : name.includes('auth.middleware') ? { requireAuth: () => {}, requireRoles: () => () => {} } : {},
    module: { exports: {} },
  });
  let status = 200;
  let payload;
  const res = { status: (code) => { status = code; return res; }, json: (data) => { payload = data; return res; } };
  await handler({}, res);
  return { calls, status, payload };
}

(async () => {
  const rows = Array.from({ length: 69 }, (_, i) => ({ order_id: 69 - i, status: 'pending', final_amount: '70000' }));
  const result = await run(rows);
  assert.equal(result.status, 200);
  assert.equal(result.calls.length, 3);
  assert.equal(result.payload.data.length, 69);
  assert.equal(result.payload.data[0].id, '69');
  assert.equal(result.payload.data[0].items[0].unitPrice, 35000);
  assert.equal(result.payload.data[0].items[0].productId, '10');
  assert.equal(result.payload.data[1].items.length, 0);
  assert.equal(result.payload.data[0].totalAmount, 70000);
  const empty = await run([]);
  assert.equal(empty.calls.length, 2);
  assert.equal(empty.payload.data.length, 0);
  const legacy = await run(rows, { legacy: true });
  assert.match(legacy.calls[1].sql, /COALESCE\(o.status,/);
  const large = await run(Array.from({ length: 1001 }, (_, i) => ({ order_id: i + 1 })));
  assert.equal(large.calls.length, 5);
  assert.equal(large.calls[2].params.length, 500);
  assert.equal(large.calls[4].params.length, 1);
  const failed = await run(rows, { fail: true });
  assert.equal(failed.status, 500);
  assert.equal(failed.payload.success, false);
  console.log('PASS: pending orders use batched reads; order/item mapping, empty lists, legacy schema, batch limits and database errors verified. No live data changed.');
})().catch((error) => { console.error(error); process.exitCode = 1; });
