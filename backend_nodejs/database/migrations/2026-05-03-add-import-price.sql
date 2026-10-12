USE mini_supermarket;

SET @has_inventory_items_import_price := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'inventory_items'
    AND COLUMN_NAME = 'import_price'
);

SET @sql := IF(
  @has_inventory_items_import_price > 0,
  'SELECT ''inventory_items.import_price already exists''',
  'ALTER TABLE inventory_items ADD COLUMN import_price DECIMAL(10,2) NULL AFTER price'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_inventory_logs_import_price := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'inventory_logs'
    AND COLUMN_NAME = 'import_price'
);

SET @sql := IF(
  @has_inventory_logs_import_price > 0,
  'SELECT ''inventory_logs.import_price already exists''',
  'ALTER TABLE inventory_logs ADD COLUMN import_price DECIMAL(10,2) NULL AFTER quantity'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
