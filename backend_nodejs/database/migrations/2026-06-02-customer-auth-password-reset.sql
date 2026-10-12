USE mini_supermarket;

SET @has_users_password_hash := (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'users'
    AND COLUMN_NAME = 'password_hash'
);

SET @sql := IF(
  @has_users_password_hash > 0,
  'SELECT ''users.password_hash already exists''',
  'ALTER TABLE users ADD COLUMN password_hash VARCHAR(255) NULL AFTER password'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

UPDATE users
SET password_hash = password
WHERE password_hash IS NULL
  AND password LIKE '$2%';

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  otp_code VARCHAR(255) NOT NULL,
  type VARCHAR(20) NOT NULL,
  expired_at DATETIME NOT NULL,
  used TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_password_reset_user_type (user_id, type, used, expired_at),

  CONSTRAINT fk_password_reset_tokens_users
    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE
) ENGINE=InnoDB;
