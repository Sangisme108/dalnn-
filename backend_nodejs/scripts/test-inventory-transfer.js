const assert = require('node:assert/strict');
const { transferToShelf, transferLog } = require('../src/services/inventory-transfer.service');
const key = '11111111-1111-4111-8111-111111111111';
const body = (quantity = 2, operation_id = key) => ({ inventory_item_id: 7, quantity, operation_id });

// Transactional SQL double: FIFO source lock, rollback journal, explicit SQL whitelist.
// It exercises the real service; it does not claim to replace MySQL integration tests.
function fixture({ emptyShelf = false, failAt = '', loseCommitAck = false } = {}) {
  const source = { inventory_item_id: 7, barcode: '0007', item_name: 'Sữa', unit: 'Hộp', stock: 10,
    price: '25000.00', image_url: '/milk.jpg', category_id: 2, status: 'active' };
  const shelf = { product_id: 8, barcode: '0007', product_name: 'Sữa', unit: 'Hộp', stock: 3, price: '26000.00', status: 'active' };
  const db = { source, product: emptyShelf ? null : shelf, logs: [], active: 0, statements: [] };
  let tail = Promise.resolve();
  const pool = { async getConnection() {
    let unlock, snapshot, committed = false;
    return {
      async beginTransaction() { db.active++; },
      async execute(sql, p = []) {
        db.statements.push(sql);
        if (sql === 'SELECT * FROM inventory_items WHERE inventory_item_id = ? FOR UPDATE') {
          const previous = tail;
          tail = new Promise(resolve => { unlock = resolve; });
          await previous;
          snapshot = structuredClone({ source: db.source, product: db.product, logs: db.logs });
          return [[p[0] === 7 ? { ...db.source } : undefined].filter(Boolean)];
        }
        if (failAt && sql.startsWith(failAt)) throw new Error('Injected failure');
        if (sql.startsWith('SELECT * FROM inventory_logs WHERE inventory_item_id')) {
          assert.match(sql, /FOR UPDATE$/);
          const prefix = p[2].slice(0, -1);
          return [db.logs.filter(l => l.inventory_item_id === p[0] && l.employee_id === p[1] && l.note.startsWith(prefix))];
        }
        if (sql.startsWith('SELECT * FROM products WHERE barcode')) {
          assert.match(sql, /FOR UPDATE$/);
          return [db.product && db.product.barcode === p[0] ? [{ ...db.product }] : []];
        }
        if (sql.startsWith('SELECT * FROM products WHERE product_id')) return [db.product ? [{ ...db.product }] : []];
        if (sql.startsWith('SELECT category_id FROM categories')) return [p[0] === 2 ? [{ category_id: 2 }] : []];
        if (sql.startsWith('INSERT INTO products')) {
          db.product = { product_id: 8, product_name: p[0], barcode: p[1], image_url: p[2], price: p[3], unit: p[4], stock: p[5], category_id: p[6], status: 'active' };
          return [{ insertId: 8 }];
        }
        if (sql.startsWith('UPDATE products SET stock = stock +')) { db.product.stock += p[0]; db.product.stock_cost=p[1]; return [{ affectedRows: 1 }]; }
        if (sql.startsWith('UPDATE inventory_items SET stock = stock -')) { db.source.stock -= p[0]; db.source.stock_cost=p[1]; return [{ affectedRows: 1 }]; }
        if (sql.startsWith('INSERT INTO inventory_logs')) {
          db.logs.push({ log_id: db.logs.length + 1, inventory_item_id: p[0], product_id: p[1], employee_id: p[2], action: 'export', quantity: p[3], note: p[4], created_at: new Date().toISOString() });
          return [{ insertId: db.logs.length }];
        }
        if (sql.startsWith('SELECT * FROM inventory_logs WHERE log_id')) return [[{ ...db.logs.find(l => l.log_id === p[0]) }]];
        if (sql.startsWith('SELECT * FROM inventory_items WHERE inventory_item_id')) return [[{ ...db.source }]];
        throw new Error('Unmodelled SQL: ' + sql);
      },
      async commit() { committed = true; if (loseCommitAck) { loseCommitAck = false; throw new Error('Lost commit acknowledgement'); } },
      async rollback() { if (snapshot && !committed) Object.assign(db, snapshot); },
      release() { db.active--; if (unlock) unlock(); },
    };
  } };
  return { db, run: (b = body(), actor = 2) => transferToShelf(pool, actor, b) };
}
let count = 0;
async function test(name, fn) { await fn(); count++; console.log('PASS:', name); }
const watchdog = setTimeout(() => { console.error('Transfer tests deadlocked'); process.exit(1); }, 10000);
(async () => {
  await test('atomic move, DB metadata, preserved shelf price, JWT actor and server timestamp', async () => {
    const f = fixture();
    const r = await f.run({ ...body(), price: 1, stock: 999, employee_id: 999, created_at: '2000-01-01' });
    assert.equal(r.inventory.stock, 8); assert.equal(r.product.stock, 5); assert.equal(r.product.price, '26000.00');
    assert.equal(r.log.employee_id, 2); assert.notEqual(r.log.created_at, '2000-01-01');
    assert.equal(r.log.before_quantity, 10); assert.equal(r.log.after_quantity, 8); assert.equal(f.db.active, 0);
    assert.equal(r.log.note, 'Đưa hàng lên kệ'); assert.ok(f.db.logs[0].note.length <= 255);
  });
  await test('creation uses only warehouse DB metadata', async () => {
    const f = fixture({ emptyShelf: true }); const r = await f.run({ ...body(), category_id: 999, price: 1 });
    assert.equal(r.product.price, '25000.00'); assert.equal(r.product.category_id, 2); assert.equal(r.product.stock, 2);
  });
  await test('strict positive integer validation and UUID', async () => {
    for (const n of [0, -1, 1.5, '2', null, true, 2147483648]) {
      const f = fixture(); await assert.rejects(f.run(body(n)), e => e.status === 400); assert.equal(f.db.active, 0);
    }
    await assert.rejects(fixture().run(body(1, 'bad')), e => e.status === 400);
  });
  await test('insufficient stock leaves all data unchanged', async () => {
    const f = fixture(); await assert.rejects(f.run(body(11)), e => e.status === 409);
    assert.equal(f.db.source.stock, 10); assert.equal(f.db.product.stock, 3); assert.equal(f.db.logs.length, 0); assert.equal(f.db.active, 0);
  });
  await test('failure at every write/read after writes rolls back both balances and log', async () => {
    for (const failAt of ['UPDATE inventory_items', 'INSERT INTO inventory_logs', 'SELECT * FROM inventory_logs WHERE log_id', 'SELECT * FROM inventory_items WHERE inventory_item_id = ?']) {
      const f = fixture({ failAt }); await assert.rejects(f.run());
      assert.equal(f.db.source.stock, 10); assert.equal(f.db.product.stock, 3); assert.equal(f.db.logs.length, 0); assert.equal(f.db.active, 0);
    }
    const f = fixture({ emptyShelf: true, failAt: 'INSERT INTO inventory_logs' }); await assert.rejects(f.run()); assert.equal(f.db.product, null);
  });
  await test('concurrent employees cannot oversell warehouse', async () => {
    const f = fixture(); const r = await Promise.allSettled([f.run(body(7)), f.run(body(7), 3)]);
    assert.equal(r.filter(x => x.status === 'fulfilled').length, 1);
    assert.equal(f.db.source.stock, 3); assert.equal(f.db.product.stock, 10); assert.equal(f.db.logs.length, 1);
  });
  await test('concurrent duplicate requests execute exactly once', async () => {
    const f = fixture(); const r = await Promise.all(Array.from({ length: 15 }, () => f.run()));
    assert.equal(r.filter(x => !x.replayed).length, 1); assert.equal(f.db.logs.length, 1);
    assert.equal(f.db.source.stock, 8); assert.equal(f.db.product.stock, 5); assert.equal(f.db.active, 0);
    await assert.rejects(f.run(body(3)), e => e.status === 409);
  });
  await test('lost commit/network response retries same durable key without moving twice', async () => {
    const f = fixture({ loseCommitAck: true }); await assert.rejects(f.run());
    const r = await f.run(); assert.equal(r.replayed, true); assert.equal(f.db.source.stock, 8); assert.equal(f.db.logs.length, 1);
    // Replayed response reports current balances after a subsequent legitimate transfer.
    await f.run(body(1, '22222222-2222-4222-8222-222222222222'));
    assert.equal((await f.run()).inventory.stock, 7);
  });
  await test('inactive, missing category, incompatible unit and overflow reject safely', async () => {
    for (const mutate of [f => f.db.source.status = 'deleted', f => f.db.product.unit = 'Kg', f => f.db.product.stock = 2147483647]) {
      const f = fixture(); mutate(f); await assert.rejects(f.run(), e => e.status === 409); assert.equal(f.db.source.stock, 10);
    }
    const f = fixture({ emptyShelf: true }); f.db.source.category_id = null;
    await assert.rejects(f.run(), e => e.status === 409); assert.equal(f.db.logs.length, 0);
    assert.equal(transferLog({ note: 'Xuất kho khác' }).note, 'Xuất kho khác');
  });
  console.log(`${count} inventory transfer scenario groups passed`);
})().catch(e => { console.error(e); process.exitCode = 1; }).finally(() => clearTimeout(watchdog));
