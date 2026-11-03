const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');

async function runCase({ message, confirmedCart, unit = 'hộp', args = { productId: 1, quantity: 5 }, failReply = false, existingQuantity = 0, stock = 10 }) {
  const routes = {};
  const product = { product_id: 1, product_name: 'Dâu tây', unit, stock, status: 'active', price: 120000 };
  let writes = 0;
  let requests = 0;
  let initialConfig;
  let writeSql;
  const connection = {
    beginTransaction: async () => {}, commit: async () => {}, rollback: async () => {}, release: () => {},
    execute: async (sql) => {
      if (sql.includes('FROM products')) return [[product]];
      if (sql.includes('FROM carts')) return [[{ cart_id: 1 }]];
      if (sql.includes('SELECT quantity')) return [[{ quantity: existingQuantity }]];
      if (sql.includes('INSERT INTO cart_items')) { writes += 1; writeSql = sql; return [{}]; }
      throw new Error(`Unexpected SQL: ${sql}`);
    },
  };
  const pool = { execute: async () => [[product]], getConnection: async () => connection };
  const router = { post: (route, ...handlers) => { routes[route] = handlers.at(-1); } };
  const sandbox = {
    require: (name) => name === 'express' ? { Router: () => router } : name.includes('config/db') ? pool : name.includes('smartsales-faq') ? require('../src/config/smartsales-faq') : { requireAuth: () => {} },
    module: { exports: {} }, process: { env: { GEMINI_API_KEY: 'mock-key' } }, console: { error: () => {} }, setTimeout,
    fetch: async (_, options) => {
      requests += 1;
      if (requests === 1) initialConfig = JSON.parse(options.body);
      if (requests > 1 && failReply) throw new Error('mock model unavailable after DB commit');
      return { ok: true, json: async () => ({ candidates: [{ content: { parts: requests === 1 ? [{ functionCall: { name: 'addToCart', args } }] : [{ text: 'Phản hồi mô phỏng' }] } }] }) };
    },
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../src/routes/ai.routes.js'), 'utf8'), sandbox);
  let result;
  const res = { status: () => res, json: (value) => { result = value; return res; } };
  await routes['/chat']({ user: { id: 1 }, body: { message, confirmedCart, candidateProductIds: [1] } }, res);
  return { writes, result, initialConfig, writeSql };
}

(async () => {
  for (const message of ['Tôi có 100k mua được gì', 'k tôi k mua đâu', 'Một hộp bao nhiêu gram?', 'ok']) {
    const { writes, result } = await runCase({ message });
    assert.equal(writes, 0, message);
    assert.equal(result.data.action, null, message);
  }
  assert.equal((await runCase({ message: 'Lấy 5 cân dâu tây', unit: 'hộp' })).writes, 0);
  assert.equal((await runCase({ message: 'Lấy 5 cân dâu tây', unit: 'kg' })).writes, 1);
  const confirmedCart = { productId: 1, quantity: 5 };
  for (const message of ['đúng', 'ừ', 'ok', 'đồng ý']) {
    const { writes, result, initialConfig } = await runCase({ message, confirmedCart });
    assert.equal(writes, 1, message);
    assert.equal(result.data.action.quantity, 5);
    assert.equal(initialConfig, undefined, 'Confirmed purchase must not require a model request');
  }
  assert.equal((await runCase({ message: 'Tôi có 100k', confirmedCart })).writes, 0);
  const changedModelArgs = await runCase({ message: 'ok', confirmedCart, args: { productId: 1, quantity: 6 } });
  assert.equal(changedModelArgs.writes, 1);
  assert.equal(changedModelArgs.result.data.action.quantity, 5);
  assert.equal((await runCase({ message: 'ok', confirmedCart, existingQuantity: 8 })).writes, 0);
  const replyFailure = await runCase({ message: 'ok', confirmedCart, failReply: true });
  assert.equal(replyFailure.writes, 1);
  assert.equal(replyFailure.result.data.action.type, 'addToCart');
  assert.match(replyFailure.result.data.answer, /Đã thêm 5 hộp/);
  const setCart = await runCase({ message: 'đúng', confirmedCart: { ...confirmedCart, mode: 'set' }, existingQuantity: 8 });
  assert.equal(setCart.writes, 1);
  assert.match(setCart.writeSql, /UPDATE quantity = VALUES\(quantity\)/);
  assert.doesNotMatch(setCart.writeSql, /quantity \+/);
  assert.match(setCart.result.data.answer, /hiện có 5 hộp/);
  const addCart = await runCase({ message: 'đúng', confirmedCart, existingQuantity: 2 });
  assert.match(addCart.writeSql, /quantity \+ VALUES\(quantity\)/);
  assert.match(addCart.result.data.answer, /Tổng trong giỏ: 7/);
  console.log('PASS: 16 cases covering budget, refusal, units, confirmation, stock, set vs add and AI failures. No live DB/API used.');
})().catch((error) => { console.error(error); process.exitCode = 1; });
