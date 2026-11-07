const costing = require('./costing.service');
// Durable retry records live in the existing inventory log, in the same transaction.
// Scope: authenticated employee + immutable inventory PK + UUID.
const PREFIX = '@shelf1:';
const MAX = 2147483647;
function fail(status, message) { const e = new Error(message); e.status = status; throw e; }
function transferLog(row) {
  if (typeof row.note !== 'string' || !row.note.startsWith(PREFIX)) return row;
  try {
    const record = JSON.parse(row.note.slice(PREFIX.length));
    return { ...row, note: 'Đưa hàng lên kệ', operation_id: record.k,
      before_quantity: record.b, after_quantity: record.a };
  } catch (_) { return row; }
}
async function transferToShelf(pool, actor, body) {
  const { inventory_item_id: id, quantity, operation_id: key } = body;
  if (!Number.isSafeInteger(id) || id <= 0 || !Number.isSafeInteger(quantity) || quantity <= 0 || quantity > MAX ||
      typeof key !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(key)) {
    fail(400, 'Mã hàng, số lượng nguyên dương và mã thao tác UUID không hợp lệ');
  }
  let conn;
  try {
    conn = await pool.getConnection();
    await conn.beginTransaction();
    const [[source]] = await conn.execute('SELECT * FROM inventory_items WHERE inventory_item_id = ? FOR UPDATE', [id]);
    if (!source) fail(404, 'Không tìm thấy hàng trong kho');
    // Locking read is essential under MySQL REPEATABLE READ after waiting for another transfer.
    const [logs] = await conn.execute(
      "SELECT * FROM inventory_logs WHERE inventory_item_id = ? AND employee_id = ? AND action = 'export' AND note LIKE ? FOR UPDATE",
      [id, actor, `${PREFIX}{"k":"${key.toLowerCase()}"%`]);
    let log = logs[0];
    let product;
    if (log) {
      if (Number(log.quantity) !== -quantity) fail(409, 'Mã thao tác đã dùng với số lượng khác');
      [[product]] = await conn.execute('SELECT * FROM products WHERE product_id = ? FOR UPDATE', [log.product_id]);
      if (!product) fail(409, 'Sản phẩm của thao tác cũ không còn tồn tại');
    } else {
      if (source.status !== 'active') fail(409, 'Hàng trong kho không hoạt động');
      if (!Number.isInteger(source.stock) || source.stock < quantity) fail(409, 'Không đủ tồn kho thực tế');
      const movedCost = costing.issue(Number(source.stock), source.stock_cost, quantity);
      [[product]] = await conn.execute('SELECT * FROM products WHERE barcode = ? FOR UPDATE', [source.barcode]);
      if (product) {
        if (product.status !== 'active' || product.unit !== source.unit) fail(409, 'Sản phẩm trên kệ không hoạt động hoặc khác đơn vị');
        if (!Number.isInteger(product.stock) || product.stock < 0 || product.stock > MAX - quantity) fail(409, 'Tồn kệ không hợp lệ hoặc vượt giới hạn');
        await conn.execute('UPDATE products SET stock = stock + ?, stock_cost = ? WHERE product_id = ?', [quantity, costing.receive(Number(product.stock), product.stock_cost, movedCost.cost), product.product_id]);
      } else {
        const [[category]] = await conn.execute('SELECT category_id FROM categories WHERE category_id = ? FOR UPDATE', [source.category_id]);
        if (!category || !Number.isFinite(Number(source.price)) || Number(source.price) <= 0) fail(409, 'Hàng trong kho thiếu danh mục hoặc giá bán hợp lệ');
        const [created] = await conn.execute(
          "INSERT INTO products (product_name, barcode, image_url, price, unit, stock, category_id, stock_cost, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active')",
          [source.item_name, source.barcode, source.image_url, source.price, source.unit, quantity, source.category_id, movedCost.cost]);
        product = { product_id: created.insertId };
      }
      await conn.execute('UPDATE inventory_items SET stock = stock - ?, stock_cost = ? WHERE inventory_item_id = ?', [quantity, movedCost.remaining, id]);
      const note = PREFIX + JSON.stringify({ k: key.toLowerCase(), b: source.stock, a: source.stock - quantity });
      const [inserted] = await conn.execute(
        "INSERT INTO inventory_logs (inventory_item_id, product_id, employee_id, action, quantity, note) VALUES (?, ?, ?, 'export', ?, ?)",
        [id, product.product_id, actor, -quantity, note]);
      [[log]] = await conn.execute('SELECT * FROM inventory_logs WHERE log_id = ?', [inserted.insertId]);
      [[product]] = await conn.execute('SELECT * FROM products WHERE product_id = ?', [product.product_id]);
    }
    const [[inventory]] = await conn.execute('SELECT * FROM inventory_items WHERE inventory_item_id = ?', [id]);
    const result = { inventory, product, log: transferLog({ ...log, item_name: source.item_name, unit: source.unit }), replayed: logs.length > 0 };
    await conn.commit();
    return result;
  } catch (error) {
    if (conn) await conn.rollback();
    throw error;
  } finally { if (conn) conn.release(); }
}
module.exports = { transferToShelf, transferLog };
