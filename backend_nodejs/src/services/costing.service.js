// Inventory carrying VALUE, in cents, preserves every cent across partial issues.
// NULL means unknown; never infer opening value from today's import price.
function minor(value) {
  if (value == null) return null;
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(String(value));
  if (!match) throw Object.assign(new Error('Giá trị giá vốn không hợp lệ'), { status: 409 });
  return BigInt(match[1]) * 100n + BigInt((match[2] || '').padEnd(2, '0'));
}
function money(value) {
  if (value == null) return null;
  return `${value / 100n}.${String(value % 100n).padStart(2, '0')}`;
}
function ratio(total, numerator, denominator) {
  return (total * BigInt(numerator) + BigInt(denominator) / 2n) / BigInt(denominator);
}
function issue(stock, value, quantity) {
  if (!Number.isSafeInteger(stock) || !Number.isSafeInteger(quantity) || quantity <= 0 || quantity > stock) {
    throw Object.assign(new Error('Số lượng xuất giá vốn không hợp lệ'), { status: 409 });
  }
  const total = minor(value);
  const cost = total == null ? null : ratio(total, quantity, stock);
  return { cost: money(cost), remaining: stock === quantity ? '0.00' : money(total == null ? null : total - cost) };
}
function receive(stock, value, addedCost) {
  const existing = stock === 0 ? 0n : minor(value);
  const added = minor(addedCost);
  return money(existing == null || added == null ? null : existing + added);
}
function allocations(items, discount) {
  const total = items.reduce((s, i) => s + minor(i.subtotal), 0n);
  let cumulative = 0n, previous = 0n;
  const d = minor(discount);
  return items.map(i => {
    cumulative += minor(i.subtotal);
    const next = total === 0n ? 0n : (d * cumulative + total / 2n) / total;
    const amount = money(next - previous); previous = next; return amount;
  });
}
async function saveLines(conn, orderId, items, discount) {
  const shares = allocations(items, discount);
  for (let n = 0; n < items.length; n++) {
    const i = items[n];
    await conn.execute(`INSERT INTO order_items
      (order_id, product_id, quantity, price, subtotal, cost_amount, unit_cost, allocated_discount)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [orderId, i.productId, i.quantity, i.price, i.subtotal, i.costAmount,
      i.costAmount == null ? null : (Number(i.costAmount) / i.quantity).toFixed(6), shares[n]]);
  }
}
async function recognize(conn, orderId) {
  await conn.execute(`UPDATE orders SET recognized_at = COALESCE(recognized_at, NOW())
    WHERE order_id = ? AND reporting_version = 1 AND payment_status IN ('paid','success')
    AND order_status = 'completed' AND status NOT IN ('cancelled','rejected','refunded')`, [orderId]);
}
module.exports = { minor, money, ratio, issue, receive, allocations, saveLines, recognize };
