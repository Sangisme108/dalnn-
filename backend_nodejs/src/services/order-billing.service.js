const costing = require('./costing.service');
const { isOwner } = require('../middlewares/auth.middleware');

const MAX_MINOR = 9999999999;

function fail(message, status = 400) {
  const error = new Error(message);
  error.status = status;
  throw error;
}

function moneyMinor(value, label = 'Số tiền') {
  if (!['number', 'string'].includes(typeof value)) fail(`${label} không hợp lệ`);
  let text = String(value).trim();
  if (typeof value === 'number') {
    const scaled = value * 100;
    if (!Number.isFinite(value) || value < 0 || Math.abs(scaled - Math.round(scaled)) > 0.000001) fail(`${label} không hợp lệ`);
    // Accept only IEEE-754 noise, not an actual fractional cent from a caller.
    text = (Math.round(scaled) / 100).toFixed(2);
  }
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(text);
  if (!match) fail(`${label} phải là số không âm, tối đa 2 chữ số thập phân`);
  const minor = Number(match[1]) * 100 + Number((match[2] || '').padEnd(2, '0'));
  if (!Number.isSafeInteger(minor) || minor > MAX_MINOR) fail(`${label} vượt giới hạn cho phép`);
  return minor;
}

function quantity(value, label = 'Số lượng') {
  const number = Number(value);
  if (!['number', 'string'].includes(typeof value) || !Number.isSafeInteger(number) || number <= 0 || number > 2147483647) fail(`${label} không hợp lệ`);
  return number;
}

function groupedItems(items) {
  if (!Array.isArray(items) || !items.length || items.length > 1000) fail('Đơn hàng cần từ 1 đến 1000 dòng sản phẩm');
  const grouped = new Map();
  for (const item of items) {
    if (!item || typeof item !== 'object') fail('Sản phẩm không hợp lệ');
    const id = quantity(item.product_id ?? item.productId, 'Mã sản phẩm');
    grouped.set(id, quantity((grouped.get(id) || 0) + quantity(item.quantity)));
  }
  return [...grouped].sort(([a], [b]) => a - b);
}

async function priceItems(connection, items, { lock = true, checkStock = true } = {}) {
  const normalizedItems = [];
  let totalMinor = 0;
  // A stable lock order prevents A/B and B/A baskets from deadlocking.
  for (const [productId, count] of groupedItems(items)) {
    const [rows] = await connection.execute(
      `SELECT product_id, product_name, price, stock, status, stock_cost FROM products WHERE product_id = ?${lock ? ' FOR UPDATE' : ''}`,
      [productId],
    );
    const product = rows[0];
    if (!product || product.status !== 'active') fail(`Sản phẩm ${productId} không còn được bán`, 409);
    if (!Number.isSafeInteger(Number(product.stock)) || Number(product.stock) < 0) fail('Dữ liệu tồn kho không hợp lệ', 409);
    if (checkStock && Number(product.stock) < count) fail(`Không đủ tồn kho cho ${product.product_name}`, 409);
    const priceMinor = moneyMinor(product.price, 'Giá sản phẩm trong database');
    if (priceMinor === 0) fail('Giá sản phẩm trong database phải lớn hơn 0', 409);
    const subtotalMinor = priceMinor * count;
    totalMinor += subtotalMinor;
    if (!Number.isSafeInteger(totalMinor) || totalMinor > MAX_MINOR) fail('Tổng đơn vượt giới hạn cho phép');
    normalizedItems.push({ productId, quantity: count, price: priceMinor / 100, subtotal: subtotalMinor / 100, costAmount: checkStock ? costing.issue(Number(product.stock), product.stock_cost, count).cost : null });
  }
  return { normalizedItems, totalMinor, total: totalMinor / 100 };
}

function voucherAmount(voucher, totalMinor) {
  if (voucher.status !== 'active') fail('Voucher không còn hoạt động', 409);
  // expiry_date is DATE: the voucher remains valid for the entire DB calendar day.
  if (Number(voucher.is_expired)) fail('Voucher đã hết hạn', 409);
  if (voucher.usage_limit != null && Number(voucher.used_count || 0) >= Number(voucher.usage_limit)) fail('Voucher đã hết lượt sử dụng', 409);
  if (totalMinor < moneyMinor(voucher.min_order_amount ?? 0, 'Giá trị đơn tối thiểu')) fail('Đơn hàng chưa đạt giá trị tối thiểu của voucher');
  let discountMinor;
  if (voucher.discount_type === 'fixed') discountMinor = moneyMinor(voucher.discount_value, 'Giá trị voucher');
  else if (voucher.discount_type === 'percent') {
    const basisPoints = moneyMinor(voucher.discount_value, 'Phần trăm voucher');
    if (basisPoints > 10000) fail('Phần trăm voucher không hợp lệ');
    discountMinor = Math.floor((totalMinor * basisPoints + 5000) / 10000);
  } else fail('Loại voucher không hợp lệ');
  if (voucher.max_discount != null) discountMinor = Math.min(discountMinor, moneyMinor(voucher.max_discount, 'Mức giảm tối đa'));
  return Math.min(totalMinor, discountMinor);
}

function validateVoucherDefinition(body) {
  if (!['fixed', 'percent'].includes(body.discount_type)) fail('Loại voucher không hợp lệ');
  const value = moneyMinor(body.discount_value, 'Giá trị voucher');
  if (body.discount_type === 'percent' && value > 10000) fail('Phần trăm voucher không được vượt 100');
  moneyMinor(body.min_order_amount ?? 0, 'Giá trị đơn tối thiểu');
  if (body.max_discount != null) moneyMinor(body.max_discount, 'Mức giảm tối đa');
  if (body.usage_limit != null && (!Number.isSafeInteger(Number(body.usage_limit)) || Number(body.usage_limit) < 0)) fail('Giới hạn sử dụng voucher không hợp lệ');
}

async function applyVoucher(connection, { totalMinor, voucherId, voucherCode, customerId, consume = true }) {
  if (voucherId == null && !voucherCode) return { voucher: null, discountMinor: 0, discountAmount: 0 };
  const code = String(voucherCode || '').trim().toUpperCase();
  const id = voucherId == null ? null : quantity(voucherId, 'Mã voucher');
  const [rows] = await connection.execute(
    `SELECT *, (expiry_date IS NOT NULL AND expiry_date < CURRENT_DATE()) AS is_expired
     FROM vouchers WHERE ${id ? 'voucher_id = ?' : 'code = ?'}${consume ? ' FOR UPDATE' : ''}`,
    [id || code],
  );
  const voucher = rows[0];
  if (!voucher) fail('Voucher không tồn tại', 404);
  if (id && code && String(voucher.code).toUpperCase() !== code) fail('Mã và ID voucher không khớp');
  const discountMinor = voucherAmount(voucher, totalMinor);
  if (consume) {
    const [updated] = await connection.execute(
      `UPDATE vouchers SET used_count = COALESCE(used_count, 0) + 1 WHERE voucher_id = ?
       AND (usage_limit IS NULL OR COALESCE(used_count, 0) < usage_limit)`, [voucher.voucher_id],
    );
    if (updated.affectedRows !== 1) fail('Voucher đã hết lượt sử dụng', 409);
    if (customerId) await connection.execute(
      `INSERT INTO user_vouchers (user_id, voucher_id, used_count, last_used_at)
       VALUES (?, ?, 1, NOW()) ON DUPLICATE KEY UPDATE used_count = COALESCE(used_count, 0) + 1, last_used_at = NOW()`,
      [customerId, voucher.voucher_id],
    );
  }
  return { voucher, discountMinor, discountAmount: discountMinor / 100 };
}

function manualDiscount(user, body, totalMinor, voucherDiscountMinor) {
  // discount_amount accompanies legacy Flutter voucher previews; it is never authoritative.
  if (body.discount_amount != null) moneyMinor(body.discount_amount, 'Giảm giá gửi từ client');
  const hasVoucher = body.voucher_id != null || body.voucherId != null || Boolean(body.voucher_code || body.voucherCode);
  const requested = body.manual_discount_amount ?? (!hasVoucher ? body.discount_amount : 0) ?? 0;
  const minor = moneyMinor(requested, 'Giảm giá thủ công');
  if (minor > 0 && !isOwner(user)) fail('Chỉ Owner được giảm giá thủ công', 403);
  if (minor > totalMinor - voucherDiscountMinor) fail('Giảm giá thủ công vượt số tiền còn lại');
  return minor;
}

async function subtractStock(connection, items) {
  for (const item of items) {
    const [updated] = await connection.execute(
      "UPDATE products SET stock = stock - ? WHERE product_id = ? AND stock >= ? AND status = 'active'",
      [item.quantity, item.productId, item.quantity],
    );
    if (updated.affectedRows !== 1) fail(`Không đủ tồn kho cho sản phẩm ${item.productId}`, 409);
    await connection.execute('UPDATE products SET stock_cost = CASE WHEN stock = 0 THEN 0 WHEN stock_cost IS NULL OR ? IS NULL THEN NULL ELSE stock_cost - ? END WHERE product_id = ?', [item.costAmount, item.costAmount, item.productId]);
  }
}

async function releaseUnpaidOrder(connection, order) {
  if (['paid', 'success'].includes(String(order.payment_status).toLowerCase())) fail('Đơn đã thanh toán cần đối soát/hoàn tiền trước khi hủy hoặc từ chối', 409);
  const [items] = await connection.execute('SELECT product_id, quantity, cost_amount FROM order_items WHERE order_id = ? ORDER BY product_id FOR UPDATE', [order.order_id]);
  for (const item of items) {
    const [[product]] = await connection.execute('SELECT stock, stock_cost FROM products WHERE product_id = ? FOR UPDATE', [item.product_id]);
    const value = costing.receive(Number(product.stock), product.stock_cost, item.cost_amount);
    await connection.execute('UPDATE products SET stock = stock + ?, stock_cost = ? WHERE product_id = ?', [quantity(item.quantity), value, item.product_id]);
  }
  await require('./loyalty.service').releaseUnpaidPoints(connection, order);
}

module.exports = { MAX_MINOR, fail, moneyMinor, quantity, groupedItems, priceItems, voucherAmount, validateVoucherDefinition, applyVoucher, manualDiscount, subtractStock, releaseUnpaidOrder };
