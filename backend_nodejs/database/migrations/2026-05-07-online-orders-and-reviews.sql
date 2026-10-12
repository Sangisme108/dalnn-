USE mini_supermarket;

SET @has_orders_note := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'note'
);

SET @sql := IF(
  @has_orders_note > 0,
  'SELECT ''orders.note already exists''',
  'ALTER TABLE orders ADD COLUMN note VARCHAR(255) NULL AFTER shipping_address'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_orders_updated_at := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'updated_at'
);

SET @sql := IF(
  @has_orders_updated_at > 0,
  'SELECT ''orders.updated_at already exists''',
  'ALTER TABLE orders ADD COLUMN updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_reviews_order_id := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'reviews'
    AND COLUMN_NAME = 'order_id'
);

SET @sql := IF(
  @has_reviews_order_id > 0,
  'SELECT ''reviews.order_id already exists''',
  'ALTER TABLE reviews ADD COLUMN order_id INT NULL AFTER user_id'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_reviews_order_item_id := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'reviews'
    AND COLUMN_NAME = 'order_item_id'
);

SET @sql := IF(
  @has_reviews_order_item_id > 0,
  'SELECT ''reviews.order_item_id already exists''',
  'ALTER TABLE reviews ADD COLUMN order_item_id INT NULL AFTER order_id'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_review_order_item_idx := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'reviews'
    AND INDEX_NAME = 'idx_reviews_order_item_id'
);

SET @sql := IF(
  @has_review_order_item_idx > 0,
  'SELECT ''idx_reviews_order_item_id already exists''',
  'ALTER TABLE reviews ADD INDEX idx_reviews_order_item_id (order_item_id)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_review_unique := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'reviews'
    AND INDEX_NAME = 'uniq_review_order_item'
);

SET @sql := IF(
  @has_review_unique > 0,
  'SELECT ''uniq_review_order_item already exists''',
  'ALTER TABLE reviews ADD UNIQUE KEY uniq_review_order_item (order_item_id)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
