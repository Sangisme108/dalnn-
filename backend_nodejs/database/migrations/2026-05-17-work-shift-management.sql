USE mini_supermarket;

SET @has_work_shifts_created_at := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'work_shifts'
    AND COLUMN_NAME = 'created_at'
);

SET @sql := IF(
  @has_work_shifts_created_at > 0,
  'SELECT ''work_shifts.created_at already exists''',
  'ALTER TABLE work_shifts ADD COLUMN created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP AFTER note'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_work_shifts_updated_at := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'work_shifts'
    AND COLUMN_NAME = 'updated_at'
);

SET @sql := IF(
  @has_work_shifts_updated_at > 0,
  'SELECT ''work_shifts.updated_at already exists''',
  'ALTER TABLE work_shifts ADD COLUMN updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_work_shifts_employee_date_idx := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'work_shifts'
    AND INDEX_NAME = 'idx_work_shifts_employee_date'
);

SET @sql := IF(
  @has_work_shifts_employee_date_idx > 0,
  'SELECT ''idx_work_shifts_employee_date already exists''',
  'ALTER TABLE work_shifts ADD INDEX idx_work_shifts_employee_date (employee_id, shift_date, start_time)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
