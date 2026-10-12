USE mini_supermarket;

-- Safe additive migration for the existing orders table.
-- The current schema uses orders.order_id and orders.customer_id.
-- Do not add a second user ownership column; online orders belong to customer_id.

SET @has_orders_payment_method := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'payment_method'
);

SET @sql := IF(
  @has_orders_payment_method > 0,
  'SELECT ''orders.payment_method already exists''',
  'ALTER TABLE orders ADD COLUMN payment_method VARCHAR(50) DEFAULT ''cash'' AFTER final_amount'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_orders_order_status := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'order_status'
);

SET @sql := IF(
  @has_orders_order_status > 0,
  'SELECT ''orders.order_status already exists''',
  'ALTER TABLE orders ADD COLUMN order_status VARCHAR(50) NOT NULL DEFAULT ''waiting_confirm'' AFTER payment_status'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_orders_confirmed_by := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'confirmed_by'
);

SET @sql := IF(
  @has_orders_confirmed_by > 0,
  'SELECT ''orders.confirmed_by already exists''',
  'ALTER TABLE orders ADD COLUMN confirmed_by INT NULL AFTER shipping_address'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_orders_confirmed_at := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'confirmed_at'
);

SET @sql := IF(
  @has_orders_confirmed_at > 0,
  'SELECT ''orders.confirmed_at already exists''',
  'ALTER TABLE orders ADD COLUMN confirmed_at TIMESTAMP NULL DEFAULT NULL AFTER confirmed_by'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE orders
SET payment_status = 'pending'
WHERE payment_status IS NULL
   OR payment_status = 'unpaid';

UPDATE orders
SET payment_status = 'paid'
WHERE payment_status IN ('completed', 'success');

UPDATE orders
SET order_status = CASE
  WHEN status IN ('confirmed', 'preparing') THEN 'confirmed'
  WHEN status = 'shipping' THEN 'shipping'
  WHEN status IN ('completed', 'Hoàn thành', 'hoàn thành') THEN 'completed'
  WHEN status = 'cancelled' THEN 'cancelled'
  ELSE 'waiting_confirm'
END
WHERE order_status IS NULL
   OR order_status = ''
   OR order_status = 'waiting_confirm';

UPDATE orders
SET status = order_status
WHERE order_type = 'online';

SET @has_fk_orders_confirmed_by := (
  SELECT COUNT(*)
  FROM information_schema.REFERENTIAL_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND CONSTRAINT_NAME = 'fk_orders_confirmed_by'
);

SET @sql := IF(
  @has_fk_orders_confirmed_by > 0,
  'SELECT ''fk_orders_confirmed_by already exists''',
  'ALTER TABLE orders ADD CONSTRAINT fk_orders_confirmed_by FOREIGN KEY (confirmed_by) REFERENCES users(user_id) ON UPDATE CASCADE ON DELETE SET NULL'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
