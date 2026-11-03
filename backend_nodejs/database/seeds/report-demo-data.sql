USE mini_supermarket;

INSERT INTO categories(category_name)
VALUES
('Đồ uống'),
('Đồ ăn nhanh'),
('Gia vị'),
('Sữa'),
('Bánh kẹo'),
('Đồ gia dụng')
ON DUPLICATE KEY UPDATE category_name = VALUES(category_name);

INSERT INTO inventory_items(barcode, item_name, price, import_price, unit, stock, status)
VALUES
('893000000001', 'Coca Cola lon 330ml', 10000, 7000, 'lon', 120, 'active'),
('893000000002', 'Pepsi lon 330ml', 10000, 6800, 'lon', 110, 'active'),
('893000000003', 'Mì Hảo Hảo tôm chua cay', 4500, 3200, 'gói', 230, 'active'),
('893000000004', 'Sữa Vinamilk 180ml', 8000, 5500, 'hộp', 100, 'active'),
('893000000005', 'Bánh Oreo', 12000, 8500, 'gói', 90, 'active'),
('893000000006', 'Nước suối Lavie 500ml', 5000, 3000, 'chai', 150, 'active'),
('893000000007', 'Dầu ăn Tường An 1L', 45000, 38000, 'chai', 50, 'active')
ON DUPLICATE KEY UPDATE
  item_name = VALUES(item_name),
  price = VALUES(price),
  import_price = VALUES(import_price),
  unit = VALUES(unit),
  stock = GREATEST(stock, VALUES(stock)),
  status = 'active';

INSERT INTO products(product_name, barcode, description, image_url, price, unit, stock, min_stock, category_id, status)
VALUES
('Coca Cola lon 330ml', '893000000001', 'Nước ngọt có gas', '', 10000, 'lon', 100, 10, (SELECT category_id FROM categories WHERE category_name = 'Đồ uống'), 'active'),
('Pepsi lon 330ml', '893000000002', 'Nước ngọt có gas', '', 10000, 'lon', 100, 10, (SELECT category_id FROM categories WHERE category_name = 'Đồ uống'), 'active'),
('Mì Hảo Hảo tôm chua cay', '893000000003', 'Mì ăn liền', '', 4500, 'gói', 200, 20, (SELECT category_id FROM categories WHERE category_name = 'Đồ ăn nhanh'), 'active'),
('Sữa Vinamilk 180ml', '893000000004', 'Sữa hộp', 'assets/images/suatuoi.jpg', 8000, 'hộp', 80, 10, (SELECT category_id FROM categories WHERE category_name = 'Sữa'), 'active'),
('Bánh Oreo', '893000000005', 'Bánh quy socola', '', 12000, 'gói', 60, 10, (SELECT category_id FROM categories WHERE category_name = 'Bánh kẹo'), 'active'),
('Nước suối Lavie 500ml', '893000000006', 'Nước suối đóng chai', 'assets/products/lavie.jpg', 5000, 'chai', 120, 10, (SELECT category_id FROM categories WHERE category_name = 'Đồ uống'), 'active'),
('Dầu ăn Tường An 1L', '893000000007', 'Dầu ăn thực vật', '', 45000, 'chai', 45, 10, (SELECT category_id FROM categories WHERE category_name = 'Gia vị'), 'active')
ON DUPLICATE KEY UPDATE
  product_name = VALUES(product_name),
  price = VALUES(price),
  unit = VALUES(unit),
  stock = GREATEST(stock, VALUES(stock)),
  category_id = VALUES(category_id),
  status = 'active';

INSERT INTO inventory_logs(inventory_item_id, product_id, employee_id, action, quantity, import_price, note)
SELECT ii.inventory_item_id, p.product_id, u.user_id, 'import', 50, ii.import_price, 'Seed dữ liệu nhập kho'
FROM inventory_items ii
JOIN products p ON p.barcode = ii.barcode
JOIN users u ON u.email = 'admin@gmail.com'
WHERE ii.barcode IN ('893000000001','893000000002','893000000003','893000000004','893000000005','893000000006','893000000007')
  AND NOT EXISTS (
    SELECT 1
    FROM inventory_logs il
    WHERE il.inventory_item_id = ii.inventory_item_id
      AND il.action = 'import'
      AND il.note = 'Seed dữ liệu nhập kho'
  );

INSERT INTO orders(customer_id, employee_id, order_type, total_amount, discount_amount, final_amount, status, payment_status, shipping_address, created_at)
SELECT NULL, u.user_id, 'offline', 0, 0, 0, 'completed', 'paid', NULL, NOW() - INTERVAL n DAY
FROM users u
JOIN (
  SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
  UNION ALL SELECT 6 UNION ALL SELECT 7
) days ON 1 = 1
WHERE u.email = 'employee@gmail.com'
  AND NOT EXISTS (
    SELECT 1 FROM orders o
    WHERE o.employee_id = u.user_id
      AND o.order_type = 'offline'
      AND o.status = 'completed'
      AND o.shipping_address IS NULL
      AND DATE(o.created_at) = DATE(NOW() - INTERVAL n DAY)
  );

INSERT INTO order_items(order_id, product_id, quantity, price, subtotal)
SELECT o.order_id, p.product_id, x.quantity, p.price, p.price * x.quantity
FROM orders o
JOIN (
  SELECT 1 AS row_no, '893000000001' AS barcode, 2 AS quantity UNION ALL
  SELECT 1, '893000000003', 5 UNION ALL
  SELECT 2, '893000000002', 3 UNION ALL
  SELECT 2, '893000000004', 4 UNION ALL
  SELECT 3, '893000000005', 2 UNION ALL
  SELECT 3, '893000000006', 6 UNION ALL
  SELECT 4, '893000000001', 1 UNION ALL
  SELECT 4, '893000000007', 1 UNION ALL
  SELECT 5, '893000000003', 10 UNION ALL
  SELECT 6, '893000000004', 3 UNION ALL
  SELECT 7, '893000000006', 8
) x ON DATE(o.created_at) = DATE(NOW() - INTERVAL x.row_no DAY)
JOIN products p ON p.barcode = x.barcode
WHERE o.status = 'completed'
  AND o.payment_status = 'paid'
  AND NOT EXISTS (
    SELECT 1 FROM order_items oi
    WHERE oi.order_id = o.order_id AND oi.product_id = p.product_id
  );

UPDATE orders o
JOIN (
  SELECT order_id, SUM(subtotal) AS total
  FROM order_items
  GROUP BY order_id
) s ON s.order_id = o.order_id
SET o.total_amount = s.total,
    o.final_amount = s.total
WHERE o.status = 'completed'
  AND o.payment_status = 'paid';

INSERT INTO payments(order_id, method, amount, status, paid_at)
SELECT o.order_id, 'cash', o.final_amount, 'paid', o.created_at
FROM orders o
WHERE o.status = 'completed'
  AND o.payment_status = 'paid'
  AND NOT EXISTS (
    SELECT 1 FROM payments p WHERE p.order_id = o.order_id
  );
