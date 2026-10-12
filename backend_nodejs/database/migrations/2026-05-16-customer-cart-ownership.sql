USE mini_supermarket;

CREATE TEMPORARY TABLE tmp_keep_carts AS
SELECT user_id, MIN(cart_id) AS keep_cart_id
FROM carts
GROUP BY user_id;

UPDATE cart_items ci
JOIN carts c ON c.cart_id = ci.cart_id
JOIN tmp_keep_carts keep ON keep.user_id = c.user_id
SET ci.cart_id = keep.keep_cart_id
WHERE ci.cart_id <> keep.keep_cart_id;

CREATE TEMPORARY TABLE tmp_keep_cart_items AS
SELECT MIN(cart_item_id) AS keep_cart_item_id, cart_id, product_id, SUM(quantity) AS total_quantity
FROM cart_items
GROUP BY cart_id, product_id;

UPDATE cart_items ci
JOIN tmp_keep_cart_items keep ON keep.keep_cart_item_id = ci.cart_item_id
SET ci.quantity = keep.total_quantity;

DELETE ci
FROM cart_items ci
JOIN tmp_keep_cart_items keep
  ON keep.cart_id = ci.cart_id
 AND keep.product_id = ci.product_id
 AND keep.keep_cart_item_id <> ci.cart_item_id;

DELETE c
FROM carts c
JOIN tmp_keep_carts keep ON keep.user_id = c.user_id
WHERE c.cart_id <> keep.keep_cart_id;

DROP TEMPORARY TABLE tmp_keep_carts;
DROP TEMPORARY TABLE tmp_keep_cart_items;

SET @has_carts_user_unique := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'carts'
    AND INDEX_NAME = 'uniq_carts_user'
);

SET @sql := IF(
  @has_carts_user_unique > 0,
  'SELECT ''uniq_carts_user already exists''',
  'ALTER TABLE carts ADD UNIQUE KEY uniq_carts_user (user_id)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_cart_items_unique := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'cart_items'
    AND INDEX_NAME = 'uniq_cart_items_cart_product'
);

SET @sql := IF(
  @has_cart_items_unique > 0,
  'SELECT ''uniq_cart_items_cart_product already exists''',
  'ALTER TABLE cart_items ADD UNIQUE KEY uniq_cart_items_cart_product (cart_id, product_id)'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
