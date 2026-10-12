const express = require("express");
const pool = require("../config/db");
const { requireAuth } = require("../middlewares/auth.middleware");

const router = express.Router();

const paymentJoinSql = `
  LEFT JOIN (
    SELECT p1.order_id, p1.method, p1.status
    FROM payments p1
    JOIN (
      SELECT order_id, MAX(payment_id) AS payment_id
      FROM payments
      GROUP BY order_id
    ) latest ON latest.payment_id = p1.payment_id
  ) pay ON pay.order_id = o.order_id
`;

function currentUserId(req) {
  return Number(req.user?.id || req.user?.user_id || req.get("x-user-id"));
}

function displayOrderStatus(row) {
  const status = row.order_status || row.status || "pending";
  if (status === "waiting_confirm") return "pending";
  return status;
}

router.get("/", requireAuth, async (req, res) => {
  try {
    const customerId = currentUserId(req);
    if (!customerId) {
      return res
        .status(401)
        .json({ success: false, message: "Vui lòng đăng nhập" });
    }

    const [rows] = await pool.execute(
      `SELECT o.*, cu.full_name AS customer_name,
              pay.method AS latest_payment_method,
              pay.status AS latest_payment_status
       FROM orders o
       LEFT JOIN users cu ON cu.user_id = o.customer_id
       ${paymentJoinSql}
       WHERE o.customer_id = ?
       ORDER BY o.created_at DESC`,
      [customerId],
    );

    const orders = [];
    for (const row of rows) {
      const [items] = await pool.execute(
        `SELECT oi.order_item_id, oi.product_id, oi.quantity, oi.price, oi.subtotal,
                p.product_name, p.image_url
         FROM order_items oi
         JOIN products p ON p.product_id = oi.product_id
         WHERE oi.order_id = ?
         ORDER BY oi.order_item_id`,
        [row.order_id],
      );

      orders.push({
        ...row,
        id: String(row.order_id),
        customerName: row.customer_name || "Khách lẻ",
        totalAmount: Number(row.final_amount),
        payment_method:
          row.payment_method || row.latest_payment_method || "cash",
        payment_status: row.payment_status || row.latest_payment_status,
        order_status: row.order_status || row.status,
        display_order_status: displayOrderStatus(row),
        rejection_reason:
          row.rejection_reason ||
          (["rejected", "cancelled"].includes(displayOrderStatus(row))
            ? row.note
            : null),
        items: items.map((item) => ({
          ...item,
          productId: String(item.product_id),
          productName: item.product_name,
          unitPrice: Number(item.price),
          subtotal: Number(item.subtotal),
        })),
      });
    }

    res.json({ success: true, data: orders });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Lỗi lấy đơn hàng của tôi",
      error: error.message,
    });
  }
});

module.exports = router;
