USE mini_supermarket;

CREATE TABLE IF NOT EXISTS user_vouchers (
  user_voucher_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  voucher_id INT NOT NULL,
  used_count INT DEFAULT 0,
  last_used_at TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_user_voucher (user_id, voucher_id),

  CONSTRAINT fk_user_vouchers_users
    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,

  CONSTRAINT fk_user_vouchers_vouchers
    FOREIGN KEY (voucher_id)
    REFERENCES vouchers(voucher_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE
) ENGINE=InnoDB;
