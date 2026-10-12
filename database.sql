-- NOTE (SAFE INIT):
-- File nÃ y Ä‘Æ°á»£c thiáº¿t káº¿ Ä‘á»ƒ import nhiá»u láº§n mÃ  KHÃ”NG lÃ m máº¥t dá»¯ liá»‡u hiá»‡n cÃ³.
-- Náº¿u báº¡n muá»‘n xoÃ¡ sáº¡ch dá»¯ liá»‡u vÃ  táº¡o láº¡i tá»« Ä‘áº§u, hÃ£y cháº¡y `database_reset.sql` trÆ°á»›c.

CREATE DATABASE IF NOT EXISTS mini_supermarket
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE mini_supermarket;

-- KhÃ´ng DROP TABLE á»Ÿ Ä‘Ã¢y Ä‘á»ƒ trÃ¡nh máº¥t dá»¯ liá»‡u khi import láº¡i.

CREATE TABLE IF NOT EXISTS roles (
  role_id INT AUTO_INCREMENT PRIMARY KEY,
  role_name VARCHAR(50) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS users (
  user_id INT AUTO_INCREMENT PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE,
  phone VARCHAR(20) UNIQUE,
  password VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255),
  address VARCHAR(255),
  role_id INT NOT NULL,
  points INT DEFAULT 0,
  membership_code VARCHAR(50) UNIQUE,
  status VARCHAR(20) DEFAULT 'active',
  employment_type VARCHAR(20) NOT NULL DEFAULT 'full_time',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT fk_users_roles
    FOREIGN KEY (role_id)
    REFERENCES roles(role_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB;

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

CREATE TABLE IF NOT EXISTS categories (
  category_id INT AUTO_INCREMENT PRIMARY KEY,
  category_name VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS products (
  product_id INT AUTO_INCREMENT PRIMARY KEY,
  product_name VARCHAR(150) NOT NULL,
  barcode VARCHAR(50) NOT NULL UNIQUE,
  description TEXT,
  image_url VARCHAR(255),
  price DECIMAL(10,2) NOT NULL,
  unit VARCHAR(50) NOT NULL DEFAULT 'sp',
  stock INT NOT NULL DEFAULT 0,
  min_stock INT DEFAULT 10,
  category_id INT NOT NULL,
  status VARCHAR(20) DEFAULT 'active',

  CONSTRAINT fk_products_categories
    FOREIGN KEY (category_id)
    REFERENCES categories(category_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS inventory_items (
  inventory_item_id INT AUTO_INCREMENT PRIMARY KEY,
  barcode VARCHAR(50) NOT NULL UNIQUE,
  item_name VARCHAR(150) NOT NULL,
  category_id INT NULL, -- <== THÃŠM DÃ’NG NÃ€Y VÃ€O ÄÃ‚Y
  image_url VARCHAR(255),
  price DECIMAL(10,2) NOT NULL,
  import_price DECIMAL(10,2) NULL,
  unit VARCHAR(50) NOT NULL DEFAULT 'sp',
  stock INT NOT NULL DEFAULT 0,
  status VARCHAR(20) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS carts (
  cart_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_carts_user (user_id),

  CONSTRAINT fk_carts_users
    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS cart_items (
  cart_item_id INT AUTO_INCREMENT PRIMARY KEY,
  cart_id INT NOT NULL,
  product_id INT NOT NULL,
  quantity INT NOT NULL DEFAULT 1,
  UNIQUE KEY uniq_cart_items_cart_product (cart_id, product_id),

  CONSTRAINT fk_cart_items_carts
    FOREIGN KEY (cart_id)
    REFERENCES carts(cart_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,

  CONSTRAINT fk_cart_items_products
    FOREIGN KEY (product_id)
    REFERENCES products(product_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS vouchers (
  voucher_id INT AUTO_INCREMENT PRIMARY KEY,
  code VARCHAR(50) NOT NULL UNIQUE,
  description TEXT,
  discount_type ENUM('fixed', 'percent') NOT NULL,
  discount_value DECIMAL(10,2) NOT NULL,
  min_order_amount DECIMAL(10,2) DEFAULT 0,
  max_discount DECIMAL(10,2) DEFAULT NULL,
  usage_limit INT DEFAULT NULL,
  used_count INT DEFAULT 0,
  expiry_date DATE DEFAULT NULL,
  status VARCHAR(20) DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS orders (
  order_id INT AUTO_INCREMENT PRIMARY KEY,
  customer_id INT,
  employee_id INT,
  shift_id INT,
  voucher_id INT, -- ThÃªm cá»™t nÃ y vÃ o Ä‘Ã¢y
  order_type VARCHAR(30) NOT NULL,
  delivery_method VARCHAR(30) DEFAULT 'pickup',
  total_amount DECIMAL(10,2) NOT NULL,
  discount_amount DECIMAL(10,2) DEFAULT 0,
  points_used INT NOT NULL DEFAULT 0,
  points_earned INT NOT NULL DEFAULT 0,
  points_discount DECIMAL(12,2) NOT NULL DEFAULT 0,
  final_amount DECIMAL(10,2) NOT NULL,
  payment_method VARCHAR(50) DEFAULT 'cash',
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  payment_status VARCHAR(50) DEFAULT 'pending',
  transaction_id VARCHAR(100),
  transfer_content VARCHAR(100),
  paid_at TIMESTAMP NULL DEFAULT NULL,
  order_status VARCHAR(50) NOT NULL DEFAULT 'waiting_confirm',
  shipping_address VARCHAR(255),
  confirmed_by INT,
  confirmed_at TIMESTAMP NULL DEFAULT NULL,
  rejection_reason VARCHAR(255),
  note VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  CONSTRAINT fk_orders_customer
    FOREIGN KEY (customer_id)
    REFERENCES users(user_id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,

  CONSTRAINT fk_orders_employee
    FOREIGN KEY (employee_id)
    REFERENCES users(user_id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,

  CONSTRAINT fk_orders_confirmed_by
    FOREIGN KEY (confirmed_by)
    REFERENCES users(user_id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,

  -- ThÃªm khÃ³a ngoáº¡i voucher vÃ o Ä‘Ã¢y
  CONSTRAINT fk_orders_vouchers
    FOREIGN KEY (voucher_id)
    REFERENCES vouchers(voucher_id)
    ON UPDATE CASCADE
    ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS order_items (
  order_item_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT NOT NULL,
  product_id INT NOT NULL,
  quantity INT NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  subtotal DECIMAL(10,2) NOT NULL,

  CONSTRAINT fk_order_items_orders
    FOREIGN KEY (order_id)
    REFERENCES orders(order_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,

  CONSTRAINT fk_order_items_products
    FOREIGN KEY (product_id)
    REFERENCES products(product_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS payments (
  payment_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT NOT NULL,
  method VARCHAR(50) NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  status VARCHAR(50) NOT NULL,
  transaction_id VARCHAR(100),
  qr_content VARCHAR(255),
  paid_at TIMESTAMP NULL DEFAULT NULL,

  CONSTRAINT fk_payments_orders
    FOREIGN KEY (order_id)
    REFERENCES orders(order_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS payment_transactions (
  id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT NULL,
  transaction_id VARCHAR(120) NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  description TEXT,
  provider VARCHAR(50) DEFAULT 'bank_webhook',
  account_number VARCHAR(50),
  raw_payload JSON NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_payment_transactions_transaction_id (transaction_id),
  KEY idx_payment_transactions_order_id (order_id),
  CONSTRAINT fk_payment_transactions_orders
    FOREIGN KEY (order_id)
    REFERENCES orders(order_id)
    ON UPDATE CASCADE
    ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS inventory_logs (
  log_id INT AUTO_INCREMENT PRIMARY KEY,
  inventory_item_id INT NOT NULL,
  product_id INT,
  employee_id INT NOT NULL,
  action VARCHAR(20) NOT NULL,
  quantity INT NOT NULL,
  import_price DECIMAL(10,2) NULL,
  note VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT fk_inventory_logs_items
    FOREIGN KEY (inventory_item_id)
    REFERENCES inventory_items(inventory_item_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,

  CONSTRAINT fk_inventory_logs_products
    FOREIGN KEY (product_id)
    REFERENCES products(product_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT,

  CONSTRAINT fk_inventory_logs_employee
    FOREIGN KEY (employee_id)
    REFERENCES users(user_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS reviews (
  review_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  order_id INT,
  order_item_id INT,
  product_id INT NOT NULL,
  rating INT NOT NULL,
  comment TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uniq_review_order_item (order_item_id),
  KEY idx_reviews_order_item_id (order_item_id),

  CONSTRAINT fk_reviews_users
    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,

  CONSTRAINT fk_reviews_products
    FOREIGN KEY (product_id)
    REFERENCES products(product_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,

  CONSTRAINT fk_reviews_orders
    FOREIGN KEY (order_id)
    REFERENCES orders(order_id)
    ON UPDATE CASCADE
    ON DELETE SET NULL,

  CONSTRAINT fk_reviews_order_items
    FOREIGN KEY (order_item_id)
    REFERENCES order_items(order_item_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS loyalty_transactions (
  loyalty_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  order_id INT,
  points_change INT NOT NULL,
  type VARCHAR(20) NOT NULL,
  note VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT fk_loyalty_transactions_users
    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
    ON UPDATE CASCADE
    ON DELETE CASCADE,

  CONSTRAINT fk_loyalty_transactions_orders
    FOREIGN KEY (order_id)
    REFERENCES orders(order_id)
    ON UPDATE CASCADE
    ON DELETE SET NULL
) ENGINE=InnoDB;

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

CREATE TABLE IF NOT EXISTS work_shifts (
  shift_id INT AUTO_INCREMENT PRIMARY KEY,
  employee_id INT NOT NULL,
  shift_date DATE NOT NULL,
  start_time TIME,
  end_time TIME,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  note VARCHAR(255),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_work_shifts_employee_date (employee_id, shift_date, start_time),

  CONSTRAINT fk_work_shifts_employee
    FOREIGN KEY (employee_id)
    REFERENCES users(user_id)
    ON UPDATE CASCADE
    ON DELETE RESTRICT
) ENGINE=InnoDB;

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

INSERT IGNORE INTO roles(role_name)
VALUES
('customer'),
('employee'),
('admin');

INSERT IGNORE INTO users(full_name, email, phone, password, password_hash, address, role_id, status)
VALUES
('Admin', 'a@gmail.com', '0900000001', '$2b$10$kB30S.076z6zgyr1G8hmguFXQ4S0csQQNBRIo7BIpN2W8aXejiHaG', '$2b$10$kB30S.076z6zgyr1G8hmguFXQ4S0csQQNBRIo7BIpN2W8aXejiHaG', 'Tai khoan quan tri', (SELECT role_id FROM roles WHERE role_name = 'admin'), 'active'),
('Nhan vien', 'b@gmail.com', '0900000002', '$2b$10$kB30S.076z6zgyr1G8hmguFXQ4S0csQQNBRIo7BIpN2W8aXejiHaG', '$2b$10$kB30S.076z6zgyr1G8hmguFXQ4S0csQQNBRIo7BIpN2W8aXejiHaG', 'Tai khoan nhan vien', (SELECT role_id FROM roles WHERE role_name = 'employee'), 'active'),
('Khach hang', 'c@gmail.com', '0900000003', '$2b$10$kB30S.076z6zgyr1G8hmguFXQ4S0csQQNBRIo7BIpN2W8aXejiHaG', '$2b$10$kB30S.076z6zgyr1G8hmguFXQ4S0csQQNBRIo7BIpN2W8aXejiHaG', 'Tai khoan khach hang', (SELECT role_id FROM roles WHERE role_name = 'customer'), 'active');
INSERT IGNORE INTO categories(category_name)
VALUES
('Äá»“ uá»‘ng'),
('TrÃ¡i cÃ¢y'),
('Gia vá»‹ xá»‘t Dh Foods');

INSERT IGNORE INTO products (
  product_name,
  barcode,
  description,
  image_url,
  price,
  unit,
  stock,
  min_stock,
  category_id,
  status
)
VALUES
-- NhÃ³m 1: TrÃ¡i cÃ¢y
('Chuá»‘i', 'PROD001', 'Chuá»‘i tÆ°Æ¡i ngon', 'assets/images/chuoi.png', 25000, 'Kg', 100, 10, (SELECT category_id FROM categories WHERE category_name = 'TrÃ¡i cÃ¢y'), 'active'),
('DÃ¢u tÃ¢y', 'PROD002', 'DÃ¢u tÃ¢y ÄÃ  Láº¡t', 'assets/images/dautay.jpg', 120000, 'Há»™p', 50, 5, (SELECT category_id FROM categories WHERE category_name = 'TrÃ¡i cÃ¢y'), 'active'),
('TÃ¡o', 'PROD003', 'TÃ¡o nháº­p kháº©u', 'assets/images/tao.png', 60000, 'Kg', 80, 10, (SELECT category_id FROM categories WHERE category_name = 'TrÃ¡i cÃ¢y'), 'active'),
('Dá»©a (ThÆ¡m)', 'PROD004', 'Dá»©a máº­t ngá»t', 'assets/images/dua.jpg', 15000, 'Quáº£', 40, 5, (SELECT category_id FROM categories WHERE category_name = 'TrÃ¡i cÃ¢y'), 'active'),
('DÆ°a háº¥u', 'PROD005', 'DÆ°a háº¥u Long An', 'assets/images/duahau.jpg', 20000, 'Kg', 150, 15, (SELECT category_id FROM categories WHERE category_name = 'TrÃ¡i cÃ¢y'), 'active'),
-- NhÃ³m 2: Gia vá»‹ xá»‘t Dh Foods
('Xá»‘t ThÃ¡i sáº£ táº¯c', 'PROD006', 'Xá»‘t Dh Foods vá»‹ ThÃ¡i', 'assets/images/xotthaixatac.jpg', 35000, 'Chai', 60, 5, (SELECT category_id FROM categories WHERE category_name = 'Gia vá»‹ xá»‘t Dh Foods'), 'active'),
('Xá»‘t BBQ', 'PROD007', 'Xá»‘t Æ°á»›p BBQ Dh Foods', 'assets/images/XotBBQ.png', 45000, 'Chai', 40, 5, (SELECT category_id FROM categories WHERE category_name = 'Gia vá»‹ xá»‘t Dh Foods'), 'active'),
('Muá»‘i á»›t chanh Nha Trang', 'PROD008', 'Muá»‘i cháº¥m háº£i sáº£n', 'assets/images/muoiotchanh.png', 18000, 'Chai', 100, 10, (SELECT category_id FROM categories WHERE category_name = 'Gia vá»‹ xá»‘t Dh Foods'), 'active'),
('Xá»‘t kim quáº¥t', 'PROD009', 'Xá»‘t kim quáº¥t Dh Foods', 'assets/images/xotkimquat.jpg', 35000, 'Chai', 50, 5, (SELECT category_id FROM categories WHERE category_name = 'Gia vá»‹ xá»‘t Dh Foods'), 'active'),
('Xá»‘t trá»©ng muá»‘i', 'PROD010', 'Xá»‘t trá»©ng muá»‘i bÃ©o ngáº­y', 'assets/images/sottrungmuoi.png', 55000, 'Chai', 30, 5, (SELECT category_id FROM categories WHERE category_name = 'Gia vá»‹ xá»‘t Dh Foods'), 'active'),
-- NhÃ³m 3: Äá»“ uá»‘ng
('TrÃ  TH true TEA', 'PROD011', 'TrÃ  xanh/Ã” long TH', 'assets/images/trathtruetea.jpg', 10000, 'Chai', 200, 20, (SELECT category_id FROM categories WHERE category_name = 'Äá»“ uá»‘ng'), 'active'),
('TrÃ  Ä‘Ã o vÃ  háº¡t chia Fuze Tea', 'PROD012', 'TrÃ  Ä‘Ã o háº¡t chia', 'assets/images/tradaohatchia.jpg', 12000, 'Chai', 120, 20, (SELECT category_id FROM categories WHERE category_name = 'Äá»“ uá»‘ng'), 'active'),
('TrÃ  xanh C2 hÆ°Æ¡ng chanh', 'PROD013', 'TrÃ  xanh C2', 'assets/images/C2.jpg', 8000, 'Chai', 300, 50, (SELECT category_id FROM categories WHERE category_name = 'Äá»“ uá»‘ng'), 'active'),
('TrÃ  Ä‘Ã¡ TRADA hÆ°Æ¡ng hoa nhÃ i', 'PROD014', 'TrÃ  Ä‘Ã¡ lon TRADA', 'assets/images/trahoanhai.png', 10000, 'Lon', 100, 15, (SELECT category_id FROM categories WHERE category_name = 'Äá»“ uá»‘ng'), 'active'),
('TrÃ  xanh Lipton vá»‹ chanh máº­t ong', 'PROD015', 'Lipton chai tiá»‡n lá»£i', 'assets/images/trachanhmatong.jpg', 12000, 'Chai', 150, 20, (SELECT category_id FROM categories WHERE category_name = 'Äá»“ uá»‘ng'), 'active');

INSERT IGNORE INTO inventory_items (barcode, item_name, image_url, price, import_price, unit, stock, status)
VALUES
('PROD001', 'Chuá»‘i', 'assets/images/chuoi.png', 25000, 15000, 'Kg', 100, 'available'),
('PROD002', 'DÃ¢u tÃ¢y', 'assets/images/dautay.jpg', 120000, 80000, 'Há»™p', 50, 'available'),
('PROD003', 'TÃ¡o', 'assets/images/tao.png', 60000, 40000, 'Kg', 80, 'available'),
('PROD004', 'Dá»©a (ThÆ¡m)', 'assets/images/dua.jpg', 15000, 8000, 'Quáº£', 40, 'available'),
('PROD005', 'DÆ°a háº¥u', 'assets/images/duahau.jpg', 20000, 12000, 'Kg', 150, 'available'),
('PROD006', 'Xá»‘t ThÃ¡i sáº£ táº¯c', 'assets/images/xotthaixatac.jpg', 35000, 25000, 'Chai', 60, 'available'),
('PROD007', 'Xá»‘t BBQ', 'assets/images/XotBBQ.png', 45000, 32000, 'Chai', 40, 'available'),
('PROD008', 'Muá»‘i á»›t chanh Nha Trang', 'assets/images/muoiotchanh.png', 18000, 12000, 'Chai', 100, 'available'),
('PROD009', 'Xá»‘t kim quáº¥t', 'assets/images/xotkimquat.jpg', 35000, 25000, 'Chai', 50, 'available'),
('PROD010', 'Xá»‘t trá»©ng muá»‘i', 'assets/images/sottrungmuoi.png', 55000, 40000, 'Chai', 30, 'available'),
('PROD011', 'TrÃ  TH true TEA', 'assets/images/trathtruetea.jpg', 10000, 7000, 'Chai', 200, 'available'),
('PROD012', 'TrÃ  Ä‘Ã o vÃ  háº¡t chia Fuze Tea', 'assets/images/tradaohatchia.jpg', 12000, 8500, 'Chai', 120, 'available'),
('PROD013', 'TrÃ  xanh C2 hÆ°Æ¡ng chanh', 'assets/images/C2.jpg', 8000, 5500, 'Chai', 300, 'available'),
('PROD014', 'TrÃ  Ä‘Ã¡ TRADA hÆ°Æ¡ng hoa nhÃ i', 'assets/images/trahoanhai.png', 10000, 6500, 'Lon', 100, 'available'),
('PROD015', 'TrÃ  xanh Lipton vá»‹ chanh máº­t ong', 'assets/images/trachanhmatong.jpg', 12000, 8000, 'Chai', 150, 'available');
UPDATE inventory_items ii
JOIN products p ON p.barcode = ii.barcode
SET ii.category_id = p.category_id
WHERE ii.category_id IS NULL;
