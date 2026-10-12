const express = require('express');
const pool = require('../config/db');
const { requireAuth } = require('../middlewares/auth.middleware');

const router = express.Router();

router.get('/products/:productId', async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT
         r.review_id,
         r.user_id AS customer_id,
         r.user_id,
         r.product_id,
         r.order_id,
         r.order_item_id,
         r.rating,
         r.comment,
         r.created_at,
         u.full_name,
         u.full_name AS customer_name
       FROM reviews r
       JOIN users u ON u.user_id = r.user_id
       WHERE r.product_id = ?
       ORDER BY r.created_at DESC`,
      [req.params.productId]
    );
    res.json({ success: true, data: rows });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi lấy đánh giá', error: error.message });
  }
});

router.post('/', requireAuth, async (req, res) => {
  try {
    if (req.user.role_name !== 'customer') {
      return res.status(403).json({ success: false, message: 'Chỉ khách hàng được đánh giá sản phẩm' });
    }

    const rawOrderId = req.body.order_id ?? req.body.orderId;
    const orderId = rawOrderId == null || rawOrderId === '' ? null : Number(rawOrderId);
    const productId = Number(req.body.product_id || req.body.productId);
    const rating = Number(req.body.rating);
    const comment = (req.body.comment || '').toString().trim();

    if (!productId || rating < 1 || rating > 5) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập product_id và rating 1-5' });
    }
    if (!comment) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập nội dung đánh giá' });
    }

    const [products] = await pool.execute(
      `SELECT product_id
       FROM products
       WHERE product_id = ? AND status <> 'deleted'
       LIMIT 1`,
      [productId]
    );
    if (products.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy sản phẩm' });
    }

    if (!orderId) {
      const [result] = await pool.execute(
        `INSERT INTO reviews (user_id, product_id, rating, comment)
         VALUES (?, ?, ?, ?)`,
        [req.user.user_id, productId, rating, comment]
      );
      const [rows] = await pool.execute(
        `SELECT
           r.review_id,
           r.user_id AS customer_id,
           r.user_id,
           r.product_id,
           r.order_id,
           r.order_item_id,
           r.rating,
           r.comment,
           r.created_at,
           u.full_name,
           u.full_name AS customer_name
         FROM reviews r
         JOIN users u ON u.user_id = r.user_id
         WHERE r.review_id = ?
         LIMIT 1`,
        [result.insertId]
      );
      return res.status(201).json({ success: true, message: 'Đã gửi đánh giá', data: rows[0] });
    }

    const [items] = await pool.execute(
      `SELECT oi.order_item_id
       FROM order_items oi
       JOIN orders o ON o.order_id = oi.order_id
       WHERE o.order_id = ?
         AND o.customer_id = ?
         AND o.status = 'completed'
         AND oi.product_id = ?
       LIMIT 1`,
      [orderId, req.user.user_id, productId]
    );
    if (items.length === 0) {
      return res.status(403).json({
        success: false,
        message: 'Bạn chỉ được đánh giá sản phẩm đã mua trong đơn hoàn thành',
      });
    }

    const orderItemId = items[0].order_item_id;
    const [existing] = await pool.execute(
      'SELECT review_id FROM reviews WHERE order_item_id = ? LIMIT 1',
      [orderItemId]
    );
    if (existing.length > 0) {
      return res.status(409).json({ success: false, message: 'Sản phẩm trong đơn hàng này đã được đánh giá' });
    }

    const [result] = await pool.execute(
      `INSERT INTO reviews (user_id, order_id, order_item_id, product_id, rating, comment)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [req.user.user_id, orderId, orderItemId, productId, rating, comment]
    );
    const [rows] = await pool.execute(
      `SELECT
         r.review_id,
         r.user_id AS customer_id,
         r.user_id,
         r.product_id,
         r.order_id,
         r.order_item_id,
         r.rating,
         r.comment,
         r.created_at,
         u.full_name,
         u.full_name AS customer_name
       FROM reviews r
       JOIN users u ON u.user_id = r.user_id
       WHERE r.review_id = ?
       LIMIT 1`,
      [result.insertId]
    );
    res.status(201).json({ success: true, message: 'Đã gửi đánh giá', data: rows[0] });
  } catch (error) {
    const status = error.code === 'ER_DUP_ENTRY' ? 409 : 500;
    res.status(status).json({ success: false, message: 'Lỗi gửi đánh giá', error: error.message });
  }
});

module.exports = router;
