-- Lịch làm mặc định + ngày nghỉ/ốm do admin chặn bắt đầu ca

SET @has_employment_type := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'employment_type'
);

SET @sql_employment_type := IF(
  @has_employment_type > 0,
  'SELECT ''users.employment_type exists''',
  'ALTER TABLE users ADD COLUMN employment_type VARCHAR(20) NOT NULL DEFAULT ''full_time'' AFTER status'
);
PREPARE stmt FROM @sql_employment_type;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE users u
JOIN roles r ON r.role_id = u.role_id
SET u.employment_type = 'full_time'
WHERE r.role_name = 'employee' AND (u.employment_type IS NULL OR u.employment_type = '');

CREATE TABLE IF NOT EXISTS employee_day_overrides (
  override_id INT AUTO_INCREMENT PRIMARY KEY,
  employee_id INT NOT NULL,
  work_date DATE NOT NULL,
  day_status VARCHAR(20) NOT NULL COMMENT 'leave | sick | blocked',
  note VARCHAR(255),
  set_by INT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  UNIQUE KEY uk_employee_work_date (employee_id, work_date),
  CONSTRAINT fk_day_override_employee
    FOREIGN KEY (employee_id) REFERENCES users(user_id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_day_override_set_by
    FOREIGN KEY (set_by) REFERENCES users(user_id)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;
