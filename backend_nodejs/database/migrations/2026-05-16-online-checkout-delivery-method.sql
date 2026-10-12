USE mini_supermarket;

SET @has_orders_delivery_method := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'delivery_method'
);

SET @sql := IF(
  @has_orders_delivery_method > 0,
  'SELECT ''orders.delivery_method already exists''',
  'ALTER TABLE orders ADD COLUMN delivery_method VARCHAR(30) DEFAULT ''pickup'' AFTER order_type'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
