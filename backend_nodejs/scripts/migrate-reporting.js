const definitions = {
  products: { stock_cost: 'DECIMAL(18,2) NULL' },
  inventory_items: { stock_cost: 'DECIMAL(18,2) NULL' },
  order_items: { cost_amount: 'DECIMAL(18,2) NULL', unit_cost: 'DECIMAL(18,6) NULL', allocated_discount: 'DECIMAL(12,2) NULL' },
  orders: { voucher_discount: 'DECIMAL(12,2) NULL', manual_discount: 'DECIMAL(12,2) NULL', recognized_at: 'DATETIME NULL', reporting_version: 'TINYINT NULL', refund_status: 'VARCHAR(16) NULL' },
};
async function migrate(pool) {
  for (const [table, columns] of Object.entries(definitions)) {
    const [existing] = await pool.execute('SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', [table]);
    const names = new Set(existing.map(c => c.COLUMN_NAME));
    for (const [name, type] of Object.entries(columns)) if (!names.has(name)) {
      await pool.execute(`ALTER TABLE ${table} ADD COLUMN ${name} ${type}`);
    }
  }
  await pool.execute(`CREATE TABLE IF NOT EXISTS sales_refunds (
    refund_id INT AUTO_INCREMENT PRIMARY KEY, order_id INT NOT NULL, employee_id INT NOT NULL,
    operation_id CHAR(36) NOT NULL, request_hash CHAR(64) NOT NULL,
    amount DECIMAL(12,2) NOT NULL, gross_return DECIMAL(12,2) NOT NULL,
    cost_reversal DECIMAL(18,2) NULL, points_returned INT NOT NULL, points_revoked INT NOT NULL,
    reason VARCHAR(255) NOT NULL, refund_reference VARCHAR(120) NOT NULL UNIQUE, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY refund_operation (order_id, operation_id), INDEX refund_date (created_at),
    FOREIGN KEY (order_id) REFERENCES orders(order_id), FOREIGN KEY (employee_id) REFERENCES users(user_id)
  ) ENGINE=InnoDB`);
  await pool.execute(`CREATE TABLE IF NOT EXISTS sales_refund_items (
    refund_item_id INT AUTO_INCREMENT PRIMARY KEY, refund_id INT NOT NULL, order_item_id INT NOT NULL,
    quantity INT NOT NULL, restock TINYINT NOT NULL, amount DECIMAL(12,2) NOT NULL,
    gross_return DECIMAL(12,2) NOT NULL, cost_reversal DECIMAL(18,2) NULL,
    FOREIGN KEY (refund_id) REFERENCES sales_refunds(refund_id),
    FOREIGN KEY (order_item_id) REFERENCES order_items(order_item_id),
    INDEX refund_line (order_item_id)
  ) ENGINE=InnoDB`);
  await pool.execute(`CREATE TABLE IF NOT EXISTS inventory_valuations (
    valuation_id INT AUTO_INCREMENT PRIMARY KEY, location VARCHAR(16) NOT NULL, item_id INT NOT NULL,
    employee_id INT NOT NULL, operation_id CHAR(36) NOT NULL UNIQUE, quantity INT NOT NULL,
    stock_cost DECIMAL(18,2) NOT NULL, reason VARCHAR(255) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employee_id) REFERENCES users(user_id)
  ) ENGINE=InnoDB`);
}
module.exports = { migrate };
if (require.main === module) {
  const pool = require('../src/config/db');
  migrate(pool).then(() => console.log('Reporting migration applied; no historical UPDATE/backfill.'))
    .catch(e => { console.error(e.message); process.exitCode = 1; }).finally(() => pool.end());
}
