const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const assert = require('node:assert/strict');

const copy = (value) => value == null ? value : structuredClone(value);

function fixture() {
  const db = {
    products: new Map([[1, { product_id: 1, product_name: 'A', price: '20000.00', stock: 10, status: 'active' }], [2, { product_id: 2, product_name: 'B', price: '30000.00', stock: 10, status: 'active' }]]),
    users: new Map([[3, { user_id: 3, full_name: 'Customer', phone: '0900000000', points: 100, role_name: 'customer', status: 'active' }]]),
    vouchers: new Map([[1, { voucher_id: 1, code: 'TEST', status: 'active', discount_type: 'percent', discount_value: '10.00', min_order_amount: '0.00', max_discount: null, usage_limit: 10, used_count: 0, expiry_date: '2999-12-31', is_expired: 0 }]]),
    orders: new Map(), items: new Map(), payments: new Map(), ledger: new Map(), userVouchers: new Map(),
    carts: new Map([[3, [{ product_id: 1, quantity: 1 }]]]),
    queries: [], nextId: 100, nextLedger: 1, active: 0, failOn: null,
  };
  const columns = ['customer_id', 'employee_id', 'voucher_id', 'order_type', 'total_amount', 'discount_amount', 'final_amount', 'status', 'order_status', 'payment_status', 'payment_method', 'transfer_content', 'transaction_id', 'paid_at', 'points_used', 'points_earned', 'points_discount', 'delivery_method', 'pickup_time', 'voucher_discount', 'manual_discount', 'reporting_version', 'recognized_at'];
  const locks = new Map();
  function connection() {
    const held = new Set();
    const undo = [];
    let released = false;
    db.active++;
    async function lock(key) {
      if (held.has(key)) return;
      const previous = locks.get(key) || Promise.resolve();
      let resolve;
      const tail = new Promise((done) => { resolve = done; });
      locks.set(key, tail);
      await previous;
      held.add(key);
      held[key] = () => { resolve(); if (locks.get(key) === tail) locks.delete(key); };
    }
    function unlock() { for (const key of held) held[key](); held.clear(); }
    function put(map, key, value) {
      const existed = map.has(key), before = copy(map.get(key));
      undo.push(() => { if (existed) map.set(key, before); else map.delete(key); });
      if (value === undefined) map.delete(key); else map.set(key, copy(value));
    }
    const c = {
      beginTransaction: async () => {},
      commit: async () => { undo.length = 0; unlock(); },
      rollback: async () => { while (undo.length) undo.pop()(); unlock(); },
      release: () => { assert.equal(released, false, 'Connection released twice'); released = true; unlock(); db.active--; },
      execute: async (raw, params = []) => {
        const sql = raw.replace(/\s+/g, ' ').trim();
        db.queries.push({ sql, params: copy(params) });
        if (db.failOn && sql.includes(db.failOn)) throw new Error('Injected SQL failure');
        if (sql.includes('information_schema.COLUMNS')) {
          if (sql.includes('COUNT(*)')) return [[{ count: 0 }]];
          return [(sql.includes("TABLE_NAME = 'payments'") ? ['transaction_id', 'qr_content', 'paid_at'] : columns).map((COLUMN_NAME) => ({ COLUMN_NAME }))];
        }
        if (sql.startsWith('SELECT shift_id')) return [[]];
        if (sql.startsWith('SELECT') && sql.includes('FROM products WHERE product_id = ?')) {
          if (sql.includes('FOR UPDATE')) await lock('product:' + params[0]);
          return [[copy(db.products.get(Number(params[0])))].filter(Boolean)];
        }
        if (sql.startsWith('UPDATE products SET stock_cost')) {
          const id=Number(params[2]); await lock('product:'+id); const p=db.products.get(id);
          const value=p.stock===0?'0.00':p.stock_cost==null||params[0]==null?null:(Number(p.stock_cost)-Number(params[0])).toFixed(2);
          put(db.products,id,{...p,stock_cost:value});return [{affectedRows:1}];
        }
        if (sql.startsWith('UPDATE products')) {
          const id = Number(sql.includes('stock_cost = ?')?params[2]:params[1]); await lock('product:' + id);
          const product = db.products.get(id);
          const subtract = sql.includes('stock - ?');
          if (!product || (subtract && (product.stock < params[2] || product.status !== 'active'))) return [{ affectedRows: 0 }];
          put(db.products, id, { ...product, stock: product.stock + (subtract ? -params[0] : params[0]), ...(sql.includes('stock_cost = ?')?{stock_cost:params[1]}:{}) });
          return [{ affectedRows: 1 }];
        }
        if (sql.startsWith('SELECT') && sql.includes('FROM vouchers WHERE')) {
          const voucher = sql.includes('voucher_id = ?') ? db.vouchers.get(Number(params[0])) : [...db.vouchers.values()].find((v) => v.code === params[0]);
          if (voucher && sql.includes('FOR UPDATE')) await lock('voucher:' + voucher.voucher_id);
          return [voucher ? [copy(db.vouchers.get(voucher.voucher_id))] : []];
        }
        if (sql.startsWith('UPDATE vouchers SET used_count')) {
          const id = Number(params[0]); await lock('voucher:' + id);
          const voucher = db.vouchers.get(id);
          if (voucher.usage_limit != null && voucher.used_count >= voucher.usage_limit) return [{ affectedRows: 0 }];
          put(db.vouchers, id, { ...voucher, used_count: voucher.used_count + 1 }); return [{ affectedRows: 1 }];
        }
        if (sql.startsWith('INSERT INTO user_vouchers')) {
          const key = params[0] + ':' + params[1]; put(db.userVouchers, key, (db.userVouchers.get(key) || 0) + 1); return [{ affectedRows: 1 }];
        }
        if (sql.startsWith('SELECT') && sql.includes('FROM carts')) {
          if (sql.includes('FOR UPDATE')) await lock('cart:' + params[0]);
          return [db.carts.has(Number(params[0])) ? [{ cart_id: Number(params[0]) }] : []];
        }
        if (sql.startsWith('SELECT') && sql.includes('FROM cart_items')) return [copy(db.carts.get(Number(params[0])) || [])];
        if (sql.startsWith('DELETE FROM cart_items')) { put(db.carts, Number(params[0]), []); return [{ affectedRows: 1 }]; }
        if (sql.startsWith('SELECT') && (sql.includes('FROM users u') || sql.includes('FROM users WHERE'))) {
          let user = sql.includes('u.phone = ?') ? [...db.users.values()].find((u) => u.phone === params[0]) : db.users.get(Number(params[0]));
          if (user && sql.includes('FOR UPDATE')) { await lock('user:' + user.user_id); user = db.users.get(user.user_id); }
          if (sql.includes("r.role_name = 'customer'") && user?.role_name !== 'customer') user = null;
          return [user ? [copy(user)] : []];
        }
        if (sql.startsWith('UPDATE users SET points')) {
          const id = Number(params[1]); await lock('user:' + id);
          const user = db.users.get(id);
          if (sql.includes('AND points >= ?') && user.points < params[2]) return [{ affectedRows: 0 }];
          const points = sql.includes('points - ?') ? user.points - params[0] : sql.includes('points + ?') ? user.points + params[0] : params[0];
          put(db.users, id, { ...user, points }); return [{ affectedRows: 1 }];
        }
        if (sql.startsWith('UPDATE users SET full_name')) { const u = db.users.get(params[1]); put(db.users, params[1], { ...u, full_name: params[0] }); return [{ affectedRows: 1 }]; }
        if (sql.startsWith('SELECT') && sql.includes('FROM loyalty_transactions')) {
          const type = params[1] || /type = '([^']+)'/.exec(sql)?.[1];
          return [[...db.ledger.values()].filter((l) => l.order_id === Number(params[0]) && l.type === type).map(copy)];
        }
        if (sql.startsWith('INSERT INTO loyalty_transactions')) {
          const type = /VALUES \(\?, \?, \?, '([^']+)'/.exec(sql)[1];
          const id = db.nextLedger++; put(db.ledger, id, { loyalty_id: id, user_id: params[0], order_id: params[1], points_change: params[2], type }); return [{ insertId: id }];
        }
        if (sql.startsWith('INSERT INTO orders')) {
          const keys = /INSERT INTO orders \(([^)]+)\)/.exec(sql)[1].split(',').map((s) => s.trim());
          const id = db.nextId++; const row = Object.fromEntries(keys.map((key, i) => [key, params[i]]));
          put(db.orders, id, { ...row, order_id: id }); return [{ insertId: id }];
        }
        if (sql.startsWith('UPDATE orders SET recognized_at')) {
          const id=Number(params[0]),o=db.orders.get(id);
          if(o?.reporting_version===1&&['paid','success'].includes(o.payment_status)&&o.order_status==='completed')put(db.orders,id,{...o,recognized_at:o.recognized_at||new Date()});
          return [{affectedRows:1}];
        }
        if (sql.startsWith('UPDATE orders SET')) {
          const id = Number(params.at(-1)); await lock('order:' + id); const row = { ...db.orders.get(id) };
          let index = 0;
          for (const part of sql.slice('UPDATE orders SET '.length).split(' WHERE ')[0].split(',')) {
            const key = part.trim().split(' ')[0];
            if (part.includes('?')) row[key] = params[index++];
            else if (part.includes("'paid'")) row[key] = 'paid';
          }
          put(db.orders, id, row); return [{ affectedRows: 1 }];
        }
        if (sql.startsWith('SELECT') && (sql.includes('FROM orders o') || sql.includes('FROM orders WHERE') || sql.includes('FROM orders WHERE'))) {
          const id = Number(params[0]); if (sql.includes('FOR UPDATE')) await lock('order:' + id);
          const row = db.orders.get(id);
          return [row ? [{ ...copy(row), ...(sql.includes('cu.points AS customer_points_balance') ? { customer_points_balance: db.users.get(row.customer_id)?.points ?? null } : {}) }] : []];
        }
        if (sql.startsWith('INSERT INTO order_items')) {
          const [order_id, product_id, quantity, price, subtotal, cost_amount, unit_cost, allocated_discount] = params;
          put(db.items, order_id, [...(db.items.get(order_id) || []), { order_id, product_id, quantity, price, subtotal, cost_amount, unit_cost, allocated_discount }]); return [{ affectedRows: 1 }];
        }
        if (sql.startsWith('SELECT') && sql.includes('FROM order_items')) return [(db.items.get(Number(params[0])) || []).map((i) => ({ ...copy(i), product_name: db.products.get(i.product_id)?.product_name }))];
        if (sql.startsWith('INSERT INTO payments')) { put(db.payments, params[0], copy(params)); return [{ affectedRows: 1 }]; }
        throw new Error('Unexpected SQL in billing fixture: ' + sql);
      },
    };
    return c;
  }
  const pool = { getConnection: async () => connection(), execute: async (...args) => { const c = connection(); try { return await c.execute(...args); } finally { c.release(); } } };
  const src = path.resolve(__dirname, '../../src');
  const cache = new Map(), routes = {};
  function load(file) {
    const absolute = path.resolve(file);
    if (absolute === path.join(src, 'config/db.js')) return pool;
    if (absolute === path.join(src, 'config/jwt.js')) return { secret: 'billing-test-only-key' };
    if (cache.has(absolute)) return cache.get(absolute).exports;
    const module = { exports: {} }; cache.set(absolute, module); const localRequire = createRequire(absolute);
    vm.runInNewContext(fs.readFileSync(absolute, 'utf8'), {
      require: (name) => name === 'express' ? { Router: () => {
        const router = Object.fromEntries(['get', 'post', 'put', 'patch', 'delete'].map((method) => [method, (route, ...handlers) => { routes[method + ' ' + route] = handlers.at(-1); }]));
        router.use = () => {}; return router;
      } } : name.startsWith('.') ? load(require.resolve(path.resolve(path.dirname(absolute), name))) : localRequire(name),
      module, exports: module.exports, process: { env: { NODE_ENV: 'test' } }, console: { log: () => {}, warn: () => {}, error: () => {} }, Buffer, URL, Date,
    }, { filename: absolute });
    return module.exports;
  }
  load(path.join(src, 'routes/order.routes.js'));
  load(path.join(src, 'routes/point.routes.js'));
  const billing = load(path.join(src, 'services/order-billing.service.js'));
  const loyalty = load(path.join(src, 'services/loyalty.service.js'));
  const payment = load(path.join(src, 'services/order-payment.service.js'));
  async function invoke(key, body = {}, user = { user_id: 2, id: 2, role_name: 'employee' }, id = '100') {
    let status = 200, data;
    const res = { status: (code) => { status = code; return res; }, json: (value) => { data = value; return res; } };
    await routes[key]({ body, user, params: { id }, get: () => undefined }, res);
    return { status, data };
  }
  return { db, pool, invoke, billing, loyalty, payment, load, src };
}

module.exports = { fixture };
