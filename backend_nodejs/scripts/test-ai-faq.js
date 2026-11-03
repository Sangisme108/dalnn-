const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const faq = require('../src/config/smartsales-faq');

async function ask({ message, maxPrice, noKey = false, quota = false, failVouchers = false, vouchers = [] }) {
  const routes = {};
  let modelRequest;
  let status = 200;
  let result;
  const router = { post: (route, ...handlers) => { routes[route] = handlers.at(-1); } };
  const pool = { execute: async (sql) => {
    assert.match(sql.trim(), /^SELECT/, 'FAQ must never mutate the database');
    if (sql.includes('FROM vouchers')) {
      assert.match(sql, /status = 'active'/);
      assert.match(sql, /expiry_date >= CURDATE/);
      assert.match(sql, /used_count < usage_limit/);
      if (failVouchers) throw new Error('Mock voucher lookup failed');
      return [vouchers];
    }
    return [[
      { product_id: 1, product_name: 'Táo', price: 60000, unit: 'kg', stock: 10 },
      { product_id: 2, product_name: 'Dâu tây', price: 120000, unit: 'hộp', stock: 10 },
    ]];
  } };
  const sandbox = {
    require: (name) => name === 'express' ? { Router: () => router } : name.includes('config/db') ? pool : name.includes('smartsales-faq') ? faq : { requireAuth: () => {} },
    module: { exports: {} }, process: { env: noKey ? {} : { GEMINI_API_KEY: 'mock-only' } },
    console: { error: () => {} }, setTimeout: (callback) => callback(),
    fetch: async (_, options) => {
      modelRequest = JSON.parse(options.body);
      return { ok: !quota, status: quota ? 429 : 200, json: async () => quota
        ? { error: { message: 'Mock quota exceeded' } }
        : { candidates: [{ content: { parts: [{ text: 'Mock advice' }] } }] } };
    },
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../src/routes/ai.routes.js'), 'utf8'), sandbox);
  const res = { status: (value) => { status = value; return res; }, json: (value) => { result = value; return res; } };
  await routes['/sales-advice']({ body: { message, maxPrice } }, res);
  return { status, result, modelRequest };
}

(async () => {
  assert.equal(faq.examples.length, 22);
  const budget = await ask({ message: 'Tôi có 100k nên mua gì?', maxPrice: 100000 });
  assert.match(budget.modelRequest.systemInstruction.parts[0].text, /Tôi muốn nấu lẩu cho 4 người/);
  assert.match(budget.modelRequest.contents[0].parts[0].text, /Táo/);
  assert.doesNotMatch(budget.modelRequest.contents[0].parts[0].text, /Dâu tây/);
  const policy = await ask({ message: 'Shop có giao hàng không?', noKey: true });
  assert.match(policy.result.data.answer, /hỗ trợ đặt giao tận nhà/);
  const missingPolicy = await ask({ message: 'Phí ship bao nhiêu?', quota: true });
  assert.match(missingPolicy.result.data.answer, /chưa cập nhật/);
  const promo = await ask({ message: 'Có gì giảm giá?', quota: true, vouchers: [{ code: 'MOCK10', discount_type: 'percent', discount_value: 10, min_order_amount: 200000, max_discount: 30000 }] });
  assert.match(promo.result.data.answer, /MOCK10.*10%.*200000.*30000/);
  const emptyPromo = await ask({ message: 'Có ưu đãi không?', noKey: true });
  assert.match(emptyPromo.result.data.answer, /chưa thấy mã ưu đãi/);
  const failedPromo = await ask({ message: 'Có ưu đãi không?', failVouchers: true });
  assert.equal(failedPromo.status, 500);
  assert.equal(failedPromo.result.success, false);
  console.log('PASS: 6 FAQ cases; 22 examples loaded; real-data budgets, policies and promotions; no live DB/API calls.');
})().catch((error) => { console.error(error); process.exitCode = 1; });
