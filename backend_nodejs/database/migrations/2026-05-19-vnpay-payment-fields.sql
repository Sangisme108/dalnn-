-- VNPay: transaction_id + paid_at on orders; transaction_id on payments (safe, idempotent)

SET @has_orders_transaction_id := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'transaction_id'
);
SET @sql_orders_transaction_id := IF(
  @has_orders_transaction_id > 0,
  'SELECT ''orders.transaction_id already exists''',
  'ALTER TABLE orders ADD COLUMN transaction_id VARCHAR(100) NULL AFTER payment_status'
);
PREPARE stmt_orders_transaction_id FROM @sql_orders_transaction_id;
EXECUTE stmt_orders_transaction_id;
DEALLOCATE PREPARE stmt_orders_transaction_id;

SET @has_orders_paid_at := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'paid_at'
);
SET @sql_orders_paid_at := IF(
  @has_orders_paid_at > 0,
  'SELECT ''orders.paid_at already exists''',
  'ALTER TABLE orders ADD COLUMN paid_at TIMESTAMP NULL DEFAULT NULL AFTER transaction_id'
);
PREPARE stmt_orders_paid_at FROM @sql_orders_paid_at;
EXECUTE stmt_orders_paid_at;
DEALLOCATE PREPARE stmt_orders_paid_at;

SET @has_payments_transaction_id := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'payments'
    AND COLUMN_NAME = 'transaction_id'
);
SET @sql_payments_transaction_id := IF(
  @has_payments_transaction_id > 0,
  'SELECT ''payments.transaction_id already exists''',
  'ALTER TABLE payments ADD COLUMN transaction_id VARCHAR(100) NULL AFTER status'
);
PREPARE stmt_payments_transaction_id FROM @sql_payments_transaction_id;
EXECUTE stmt_payments_transaction_id;
DEALLOCATE PREPARE stmt_payments_transaction_id;
