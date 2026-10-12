-- WARNING: DESTRUCTIVE
-- File này sẽ XOÁ toàn bộ bảng và dữ liệu trong database `mini_supermarket`.
-- Chỉ dùng khi bạn muốn reset database về trạng thái trống.
-- Sau khi chạy xong file này, hãy chạy `database.sql` để tạo bảng + seed dữ liệu mẫu (an toàn).

CREATE DATABASE IF NOT EXISTS mini_supermarket
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE mini_supermarket;

SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS notifications;
DROP TABLE IF EXISTS work_shifts;
DROP TABLE IF EXISTS loyalty_transactions;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS order_discounts;
DROP TABLE IF EXISTS discount_codes;
DROP TABLE IF EXISTS inventory_logs;
DROP TABLE IF EXISTS inventory_items;
DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS cart_items;
DROP TABLE IF EXISTS carts;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS roles;

SET FOREIGN_KEY_CHECKS = 1;
