USE mini_supermarket;

SET @has_orders_payment_status := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'payment_status'
);

SET @sql_orders_payment_status_default := IF(
  @has_orders_payment_status > 0,
  'ALTER TABLE orders ALTER COLUMN payment_status SET DEFAULT ''pending''',
  'SELECT ''orders.payment_status does not exist'''
);
PREPARE stmt_orders_payment_status_default FROM @sql_orders_payment_status_default;
EXECUTE stmt_orders_payment_status_default;
DEALLOCATE PREPARE stmt_orders_payment_status_default;
