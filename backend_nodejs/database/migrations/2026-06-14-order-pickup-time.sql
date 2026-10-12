SET @has_pickup_time := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'pickup_time'
);

SET @sql := IF(
  @has_pickup_time > 0,
  'SELECT ''orders.pickup_time already exists''',
  'ALTER TABLE orders ADD COLUMN pickup_time DATETIME NULL AFTER shipping_address'
);

PREPARE statement FROM @sql;
EXECUTE statement;
DEALLOCATE PREPARE statement;
