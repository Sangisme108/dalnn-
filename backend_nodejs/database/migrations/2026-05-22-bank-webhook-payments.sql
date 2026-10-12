-- Bank transfer webhook support: transfer_content + transaction ledger.

SET @has_orders_transfer_content := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'transfer_content'
);
SET @sql_orders_transfer_content := IF(
  @has_orders_transfer_content > 0,
  'SELECT ''orders.transfer_content already exists''',
  'ALTER TABLE orders ADD COLUMN transfer_content VARCHAR(100) NULL AFTER transaction_id'
);
PREPARE stmt_orders_transfer_content FROM @sql_orders_transfer_content;
EXECUTE stmt_orders_transfer_content;
DEALLOCATE PREPARE stmt_orders_transfer_content;

CREATE TABLE IF NOT EXISTS payment_transactions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT NULL,
  transaction_id VARCHAR(120) NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  description TEXT,
  provider VARCHAR(50) DEFAULT 'bank_webhook',
  account_number VARCHAR(50),
  raw_payload JSON NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_payment_transactions_transaction_id (transaction_id),
  KEY idx_payment_transactions_order_id (order_id),
  CONSTRAINT fk_payment_transactions_orders
    FOREIGN KEY (order_id)
    REFERENCES orders(order_id)
    ON UPDATE CASCADE
    ON DELETE SET NULL
) ENGINE=InnoDB;
