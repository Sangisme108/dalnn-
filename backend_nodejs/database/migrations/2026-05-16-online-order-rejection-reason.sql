USE mini_supermarket;

SET @has_orders_rejection_reason := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'rejection_reason'
);

SET @sql := IF(
  @has_orders_rejection_reason > 0,
  'SELECT ''orders.rejection_reason already exists''',
  'ALTER TABLE orders ADD COLUMN rejection_reason VARCHAR(255) NULL'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;