USE mini_supermarket;

SET @has_work_shifts_status := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'work_shifts'
    AND COLUMN_NAME = 'status'
);

SET @sql := IF(
  @has_work_shifts_status > 0,
  'SELECT ''work_shifts.status already exists''',
  'ALTER TABLE work_shifts ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT ''active'' AFTER end_time'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := IF(
  @has_work_shifts_status > 0,
  'UPDATE work_shifts SET status = ''closed'' WHERE end_time IS NOT NULL AND (status IS NULL OR status IN (''active'', ''working''))',
  'UPDATE work_shifts SET status = ''closed'' WHERE end_time IS NOT NULL'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_orders_shift_id := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'shift_id'
);

SET @sql := IF(
  @has_orders_shift_id > 0,
  'SELECT ''orders.shift_id already exists''',
  'ALTER TABLE orders ADD COLUMN shift_id INT NULL AFTER employee_id'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_orders_shift_index := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND INDEX_NAME = 'idx_orders_shift_id'
);

SET @sql := IF(
  @has_orders_shift_index > 0,
  'SELECT ''idx_orders_shift_id already exists''',
  'ALTER TABLE orders ADD INDEX idx_orders_shift_id (shift_id)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
