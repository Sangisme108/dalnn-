const express = require('express');
const pool = require('../config/db');
const { requireAuth, requireRoles } = require('../middlewares/auth.middleware');
const loyalty = require('../services/loyalty.service');

const router = express.Router();
router.use(requireAuth, requireRoles('admin', 'employee'));

router.get('/customer', async (req, res) => {
  const phone = loyalty.normalizePhone(req.query.phone);
  const amountAfterVoucher =
    req.query.amount_after_voucher ??
    req.query.amountAfterVoucher ??
    req.query.amount;

  if (phone.length < 8 || phone.length > 15) {
    return res.status(400).json({
      success: false,
      message: 'Số điện thoại không hợp lệ',
    });
  }

  const connection = await pool.getConnection();
  try {
    const customer = await loyalty.findCustomerByPhone(connection, phone);
    if (!customer || customer.role_name !== 'customer') {
      return res.json({
        success: true,
        exists: false,
        phone,
        points: 0,
        can_redeem: false,
        max_redeem_points: 0,
        max_discount: 0,
        message: 'Khách hàng chưa có điểm, chỉ có thể tích điểm sau đơn này',
      });
    }

    const quote = loyalty.redeemQuote(
      customer.points,
      amountAfterVoucher == null || amountAfterVoucher === ''
        ? null
        : Number(amountAfterVoucher),
    );
    return res.json({
      success: true,
      exists: true,
      user_id: customer.user_id,
      name: customer.full_name,
      phone: customer.phone,
      points: Number(customer.points || 0),
      can_redeem: quote.canRedeem,
      max_redeem_points: quote.maxRedeemPoints,
      max_discount: quote.maxDiscount,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: 'Lỗi tra điểm khách hàng',
      error: error.message,
    });
  } finally {
    connection.release();
  }
});

router.post('/add', async (req, res) => {
  const orderId = Number(req.body.orderId || req.body.order_id);
  if (!Number.isSafeInteger(orderId) || orderId <= 0) return res.status(400).json({ success: false, message: 'Cần mã đơn đã thanh toán để tích điểm; không nhận số tiền tự nhập' });
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [orders] = await connection.execute('SELECT * FROM orders WHERE order_id = ? FOR UPDATE', [orderId]);
    const order = orders[0];
    if (!order || !order.customer_id) { const error = new Error('Đơn không có khách hàng tích điểm'); error.status = 409; throw error; }
    if (!['paid', 'success'].includes(String(order.payment_status).toLowerCase())) { const error = new Error('Chỉ cộng điểm cho đơn đã thanh toán'); error.status = 409; throw error; }
    const [customers] = await connection.execute('SELECT user_id, full_name, phone, points FROM users WHERE user_id = ? FOR UPDATE', [order.customer_id]);
    const customer = customers[0];
    if (!customer || (req.body.phone && loyalty.normalizePhone(req.body.phone) !== loyalty.normalizePhone(customer.phone))) { const error = new Error('Khách hàng không khớp đơn hàng'); error.status = 409; throw error; }
    const duplicate = await loyalty.transactionExists(connection, orderId, 'earn');
    const result = await loyalty.finalizePaidOrderLoyalty(connection, orderId);
    await connection.commit();
    res.json({ success: true, message: duplicate ? 'Đơn đã được tích điểm' : 'Đã tích điểm theo số tiền thực tế của đơn', data: {
      customerId: customer.user_id, customerName: customer.full_name, phone: customer.phone,
      pointsAdded: duplicate ? 0 : result?.pointsEarned || 0, totalPoints: result?.totalPoints ?? Number(customer.points), duplicate,
    } });
  } catch (error) {
    if (connection) { try { await connection.rollback(); } catch (_) {} }
    res.status(error.status || 500).json({ success: false, message: error.status ? error.message : 'Chưa tích được điểm cho đơn hàng' });
  } finally { if (connection) connection.release(); }
});

module.exports = router;
