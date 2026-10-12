-- Loyalty redemption support for POS orders.
-- Safe to run multiple times.

SET @has_orders_points_used := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'points_used'
);
SET @sql_orders_points_used := IF(
  @has_orders_points_used > 0,
  'SELECT ''orders.points_used already exists''',
  'ALTER TABLE orders ADD COLUMN points_used INT NOT NULL DEFAULT 0 AFTER discount_amount'
);
PREPARE stmt_orders_points_used FROM @sql_orders_points_used;
EXECUTE stmt_orders_points_used;
DEALLOCATE PREPARE stmt_orders_points_used;

SET @has_orders_points_earned := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'points_earned'
);
SET @sql_orders_points_earned := IF(
  @has_orders_points_earned > 0,
  'SELECT ''orders.points_earned already exists''',
  'ALTER TABLE orders ADD COLUMN points_earned INT NOT NULL DEFAULT 0 AFTER points_used'
);
PREPARE stmt_orders_points_earned FROM @sql_orders_points_earned;
EXECUTE stmt_orders_points_earned;
DEALLOCATE PREPARE stmt_orders_points_earned;

SET @has_orders_points_discount := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'points_discount'
);
SET @sql_orders_points_discount := IF(
  @has_orders_points_discount > 0,
  'SELECT ''orders.points_discount already exists''',
  'ALTER TABLE orders ADD COLUMN points_discount DECIMAL(12,2) NOT NULL DEFAULT 0 AFTER points_earned'
);
PREPARE stmt_orders_points_discount FROM @sql_orders_points_discount;
EXECUTE stmt_orders_points_discount;
DEALLOCATE PREPARE stmt_orders_points_discount;

SET @has_loyalty_order_type_idx := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'loyalty_transactions'
    AND INDEX_NAME = 'idx_loyalty_order_type'
);
SET @sql_loyalty_order_type_idx := IF(
  @has_loyalty_order_type_idx > 0,
  'SELECT ''idx_loyalty_order_type already exists''',
  'ALTER TABLE loyalty_transactions ADD INDEX idx_loyalty_order_type (order_id, type)'
);
PREPARE stmt_loyalty_order_type_idx FROM @sql_loyalty_order_type_idx;
EXECUTE stmt_loyalty_order_type_idx;
DEALLOCATE PREPARE stmt_loyalty_order_type_idx;
