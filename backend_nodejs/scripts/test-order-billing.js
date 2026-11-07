const assert = require('node:assert/strict');
const path = require('node:path');
const { fixture } = require('./helpers/billing-fixture');

let checks = 0;
const watchdog = setTimeout(() => { console.error('FAIL: billing tests timed out (possible lock deadlock)'); process.exit(1); }, 10000);
const pos = (extra = {}) => ({ items: [{ product_id: 1, quantity: 1 }], payment_method: 'cash', ...extra });
const member = { customer_id: 3, points_to_use: 100 };
const owner = { user_id: 1, id: 1, role_name: 'admin' };
async function test(name, run) { await run(); checks++; console.log('PASS:', name); }
async function reject(body, expected, prepare = () => {}) {
  const f = fixture(); prepare(f);
  const result = await f.invoke('post /', body);
  assert.equal(result.status, expected, JSON.stringify(result.data));
  assert.equal(f.db.orders.size, 0);
  assert.equal(f.db.products.get(1).stock, 10);
  assert.equal(f.db.vouchers.get(1).used_count, 0);
  assert.equal(f.db.users.get(3).points, 100);
  assert.equal(f.db.active, 0);
}

(async () => {
  await test('POS ignores forged line prices, totals, earned points and paid timestamps', async () => {
    const f = fixture();
    const result = await f.invoke('post /', pos({ items: [{ product_id: 1, quantity: 2, price: 1, subtotal: 1 }], total_amount: 1, final_amount: 1, points_earned: 999999, paid_at: '2000-01-01' }));
    assert.equal(result.status, 201, JSON.stringify(result.data));
    assert.equal(result.data.data.totalAmount, 40000);
    assert.equal(result.data.data.items[0].unitPrice, 20000);
    assert.equal(f.db.orders.get(100).total_amount, 40000);
    assert.equal(f.db.orders.get(100).final_amount, 40000);
    assert.equal(f.db.items.get(100)[0].subtotal, 40000);
    assert.equal(f.db.products.get(1).stock, 8);
    assert.equal(f.db.active, 0);
  });
  await test('bank transfers cannot be declared paid or assigned a custom DH code by the client', async () => {
    const f = fixture();
    const result = await f.invoke('post /', pos({ payment_method: 'bank_transfer', payment_status: 'paid', status: 'completed', transfer_content: 'FAKE', transaction_id: 'FAKE' }));
    assert.equal(result.status, 201);
    assert.equal(f.db.orders.get(100).payment_status, 'pending');
    assert.equal(f.db.orders.get(100).transfer_content, 'DH100');
  });
  await test('cash amount changed since client confirmation is rejected atomically', async () => {
    await reject(pos({ expected_final_amount: 1 }), 409);
  });
  await test('voucher recalculates discount from database and ignores preview amount/user-id', async () => {
    const f = fixture();
    const result = await f.invoke('post /', pos({ voucher_id: 1, discount_amount: 19999, user_id: 1, customer_id: 3 }));
    assert.equal(result.status, 201, JSON.stringify(result.data));
    assert.equal(f.db.orders.get(100).discount_amount, 2000);
    assert.equal(f.db.orders.get(100).final_amount, 18000);
    assert.equal(f.db.vouchers.get(1).used_count, 1);
    assert.equal(f.db.userVouchers.get('3:1'), 1);
    assert.equal(f.db.userVouchers.has('1:1'), false);
  });
  await test('expired, inactive, exhausted and below-minimum vouchers do not mutate data', async () => {
    await reject(pos({ voucher_id: 1 }), 409, ({ db }) => { db.vouchers.get(1).is_expired = 1; });
    await reject(pos({ voucher_id: 1 }), 409, ({ db }) => { db.vouchers.get(1).status = 'inactive'; });
    await reject(pos({ voucher_id: 1 }), 409, ({ db }) => { db.vouchers.get(1).usage_limit = 0; });
    await reject(pos({ voucher_id: 1 }), 400, ({ db }) => { db.vouchers.get(1).min_order_amount = '999999.00'; });
  });
  await test('negative/NaN/infinite discounts and invalid quantities are rejected', async () => {
    for (const discount of [-1, 'NaN', 'Infinity', null]) {
      if (discount !== null) await reject(pos({ discount_amount: discount }), 400);
    }
    for (const count of [-1, 0, 1.5, 'NaN', 'Infinity', true]) await reject(pos({ items: [{ product_id: 1, quantity: count }] }), 400);
  });
  await test('staff cannot manually discount; Owner can with bounds and an audit note', async () => {
    await reject(pos({ discount_amount: 1000 }), 403);
    await reject(pos({ voucher_id: 1, manual_discount_amount: 1000 }), 403);
    const f = fixture();
    const result = await f.invoke('post /', pos({ manual_discount_amount: 1000 }), owner);
    assert.equal(result.status, 201);
    assert.equal(f.db.orders.get(100).final_amount, 19000);
    assert.match(f.db.orders.get(100).note, /Owner #1/);
    assert.equal((await f.invoke('post /', pos({ manual_discount_amount: 999999 }), owner)).status, 400);
  });
  await test('fixed and percent discounts respect caps, zero caps and order totals', async () => {
    for (const type of ['fixed', 'percent']) {
      const f = fixture(); Object.assign(f.db.vouchers.get(1), { discount_type: type, discount_value: type === 'fixed' ? 50000 : 80, max_discount: 3000 });
      assert.equal((await f.invoke('post /', pos({ voucher_id: 1 }))).status, 201);
      assert.equal(f.db.orders.get(100).discount_amount, 3000);
    }
    const f = fixture(); Object.assign(f.db.vouchers.get(1), { max_discount: 0 });
    assert.equal((await f.invoke('post /', pos({ voucher_id: 1 }))).status, 201);
    assert.equal(f.db.orders.get(100).discount_amount, 0);
  });
  await test('decimal arithmetic is cent-exact and rounds percentage discounts once', async () => {
    const f = fixture(); f.db.products.get(1).price = '0.10';
    assert.equal((await f.invoke('post /', pos({ items: [{ product_id: 1, quantity: 3 }] }))).status, 201);
    assert.equal(f.db.orders.get(100).final_amount, 0.30);
    assert.equal(f.billing.voucherAmount({ ...f.db.vouchers.get(1), discount_value: '12.50' }, 10003), 1250);
    assert.equal(f.billing.moneyMinor(19.99 - 1.99), 1800);
    assert.throws(() => f.billing.moneyMinor(1.234));
  });
  await test('duplicate lines are grouped before checking stock; inactive products cannot sell', async () => {
    await reject(pos({ items: [{ product_id: 1, quantity: 6 }, { product_id: 1, quantity: 6 }] }), 409);
    await reject(pos(), 409, ({ db }) => { db.products.get(1).status = 'inactive'; });
    const f = fixture(); assert.equal((await f.invoke('post /', pos({ items: [{ product_id: 1, quantity: 2 }, { product_id: 1, quantity: 3 }] }))).status, 201);
    assert.equal(f.db.items.get(100).length, 1); assert.equal(f.db.products.get(1).stock, 5);
  });
  await test('SQL failure after stock/voucher/points writes rolls all changes back', async () => {
    await reject(pos({ ...member, voucher_id: 1 }), 500, ({ db }) => { db.failOn = 'INSERT INTO payments'; });
  });
  await test('invalid, excessive and negative points cannot discount an order', async () => {
    for (const points of [-100, 1.5, 'NaN', 'Infinity', 1]) await reject(pos({ customer_id: 3, points_to_use: points }), 400);
    await reject(pos({ customer_id: 3, points_to_use: 200 }), 409);
  });
  await test('concurrent orders cannot oversell the final units', async () => {
    const f = fixture(); f.db.products.get(1).stock = 3;
    const results = await Promise.all([f.invoke('post /', pos({ items: [{ product_id: 1, quantity: 2 }] })), f.invoke('post /', pos({ items: [{ product_id: 1, quantity: 2 }] }))]);
    assert.deepEqual(results.map((r) => r.status).sort(), [201, 409]);
    assert.equal(f.db.products.get(1).stock, 1); assert.equal(f.db.orders.size, 1); assert.equal(f.db.active, 0);
  });
  await test('concurrent baskets serialize the final voucher use', async () => {
    const f = fixture(); f.db.vouchers.get(1).usage_limit = 1;
    const results = await Promise.all([f.invoke('post /', pos({ voucher_id: 1 })), f.invoke('post /', pos({ voucher_id: 1, items: [{ product_id: 2, quantity: 1 }] }))]);
    assert.deepEqual(results.map((r) => r.status).sort(), [201, 409]);
    assert.equal(f.db.vouchers.get(1).used_count, 1); assert.equal(f.db.orders.size, 1); assert.equal(f.db.active, 0);
  });
  await test('concurrent pending bank orders cannot reuse the same points', async () => {
    const f = fixture();
    const results = await Promise.all([f.invoke('post /', pos({ ...member, payment_method: 'bank_transfer' })), f.invoke('post /', pos({ ...member, payment_method: 'bank_transfer', items: [{ product_id: 2, quantity: 1 }] }))]);
    assert.deepEqual(results.map((r) => r.status).sort(), [201, 409]);
    assert.equal(f.db.users.get(3).points, 0); assert.equal(f.db.orders.size, 1);
    assert.equal([...f.db.ledger.values()].filter((l) => l.type === 'redeem').length, 1);
  });
  await test('cash rewards are calculated from net amount and never awarded twice', async () => {
    const f = fixture(); const created = await f.invoke('post /', pos(member)); assert.equal(created.status, 201);
    assert.equal(created.data.data.customerPointsBalance, 1);
    assert.equal(f.db.orders.get(100).final_amount, 10000);
    assert.equal(f.db.orders.get(100).points_earned, 1); assert.equal(f.db.users.get(3).points, 1);
    for (let n = 0; n < 2; n++) { const c = await f.pool.getConnection(); await c.beginTransaction(); await f.loyalty.finalizePaidOrderLoyalty(c, 100); await c.commit(); c.release(); }
    assert.equal(f.db.users.get(3).points, 1);
    assert.equal([...f.db.ledger.values()].filter((l) => l.type === 'earn').length, 1);
    const manual = await f.invoke('post /add', { orderId: 100, amount: 99999999, phone: '0900000000', customerName: 'Fake' });
    assert.equal(manual.status, 200); assert.equal(manual.data.data.pointsAdded, 0); assert.equal(f.db.users.get(3).points, 1);
  });
  await test('pending cancellation restores reserved points/stock once and late payments cannot reopen it', async () => {
    const f = fixture(); assert.equal((await f.invoke('post /', pos({ ...member, payment_method: 'bank_transfer' }))).status, 201);
    const customer = { user_id: 3, id: 3, role_name: 'customer' };
    assert.equal((await f.invoke('put /:id/cancel', { reason: 'Mock cancel' }, customer)).status, 200);
    assert.equal(f.db.users.get(3).points, 100); assert.equal(f.db.products.get(1).stock, 10);
    assert.equal((await f.invoke('put /:id/cancel', { reason: 'Again' }, customer)).status, 409);
    const c = await f.pool.getConnection(); await c.beginTransaction();
    const late = await f.payment.markOrderPaid(c, 100, { transactionId: 'late' });
    assert.equal(late.ok, false); await c.rollback(); c.release();
    assert.equal(f.db.orders.get(100).payment_status, 'pending');
  });
  await test('concurrent payment callbacks settle once and failed callbacks cannot downgrade a paid order', async () => {
    const f = fixture(); assert.equal((await f.invoke('post /', pos({ ...member, payment_method: 'bank_transfer' }))).status, 201);
    const results = await Promise.all([1, 2].map(async (n) => {
      const c = await f.pool.getConnection(); await c.beginTransaction();
      try { const result = await f.payment.markOrderPaid(c, 100, { transactionId: 'bank-' + n }); await c.commit(); return result; }
      finally { c.release(); }
    }));
    assert.equal(results.filter((r) => r.alreadyPaid).length, 1);
    assert.equal(f.db.queries.filter((q) => q.sql.startsWith('INSERT INTO payments')).length, 2);
    assert.equal(f.db.users.get(3).points, 1);
    const c = await f.pool.getConnection(); await c.beginTransaction();
    await f.payment.markOrderFailed(c, 100, { transactionId: 'old-failed' }); await c.commit(); c.release();
    assert.equal(f.db.orders.get(100).payment_status, 'paid');
  });
  await test('online checkout uses DB cart/prices, ignores posted totals and keeps fake ewallet pending', async () => {
    const f = fixture(); const result = await f.invoke('post /checkout', { delivery_method: 'delivery', shipping_address: 'Mock address', payment_method: 'ewallet', final_amount: 1, payment_status: 'paid', voucher_code: 'TEST', discount_amount: 99999 }, { user_id: 3, id: 3, role_name: 'customer' });
    assert.equal(result.status, 201, JSON.stringify(result.data));
    assert.equal(f.db.orders.get(100).final_amount, 18000);
    assert.equal(f.db.orders.get(100).payment_status, 'pending'); assert.equal(f.db.carts.get(3).length, 0);
  });
  await test('online failure leaves cart/voucher/stock intact', async () => {
    const f = fixture(); f.db.failOn = 'INSERT INTO payments';
    const result = await f.invoke('post /checkout', { delivery_method: 'delivery', shipping_address: 'Mock', voucher_code: 'TEST' }, { user_id: 3, id: 3, role_name: 'customer' });
    assert.equal(result.status, 500); assert.equal(f.db.carts.get(3).length, 1); assert.equal(f.db.products.get(1).stock, 10); assert.equal(f.db.vouchers.get(1).used_count, 0); assert.equal(f.db.orders.size, 0);
  });
  await test('staff status changes refund unpaid reservations once and cannot reopen closed orders', async () => {
    const f = fixture(); assert.equal((await f.invoke('post /', pos({ ...member, payment_method: 'bank_transfer' }))).status, 201);
    assert.equal((await f.invoke('patch /:id/status', { status: 'cancelled' }, owner)).status, 200);
    assert.equal((await f.invoke('patch /:id/status', { status: 'cancelled' }, owner)).status, 200);
    assert.equal(f.db.users.get(3).points, 100); assert.equal(f.db.products.get(1).stock, 10);
    assert.equal((await f.invoke('patch /:id/status', { status: 'shipping' }, owner)).status, 409);
  });
  await test('paid orders require reconciliation rather than silent point/stock refunds', async () => {
    const f = fixture(); assert.equal((await f.invoke('post /', pos(member))).status, 201);
    const result = await f.invoke('put /:id/cancel', { reason: 'Mock' }, { user_id: 3, id: 3, role_name: 'customer' });
    assert.equal(result.status, 409); assert.equal(f.db.products.get(1).stock, 9); assert.equal(f.db.users.get(3).points, 1);
  });
  await test('voucher definitions reject negative limits and preserve a zero maximum', async () => {
    const f = fixture();
    for (const body of [{ discount_type: 'fixed', discount_value: -1 }, { discount_type: 'percent', discount_value: 101 }, { discount_type: 'percent', discount_value: 10, max_discount: -1 }, { discount_type: 'fixed', discount_value: 10, usage_limit: -1 }]) assert.throws(() => f.billing.validateVoucherDefinition(body));
    f.billing.validateVoucherDefinition({ discount_type: 'fixed', discount_value: 10, max_discount: 0, usage_limit: 0 });
  });
  await test('voucher preview recomputes from DB items and never consumes a voucher', async () => {
    const f = fixture(); const controller = f.load(path.join(f.src, 'controllers/voucher.controller.js'));
    let body, status = 200; const res = { status: (code) => { status = code; return res; }, json: (data) => { body = data; } };
    await controller.validateVoucher({ user: { user_id: 3 }, body: { code: 'TEST', orderTotal: 999999 } }, res);
    assert.equal(status, 200, JSON.stringify(body)); assert.equal(body.voucher.subtotal, 20000); assert.equal(body.voucher.discountAmount, 2000); assert.equal(f.db.vouchers.get(1).used_count, 0);
  });
  console.log('PASS: ' + checks + ' billing scenario groups using actual route/services and a transactional row-lock fixture. No live database/schema/payment calls.');
})().catch((error) => { console.error(error); process.exitCode = 1; }).finally(() => clearTimeout(watchdog));
