const express = require('express');
const pool = require('../config/db');
const loyalty = require('../services/loyalty.service');

const router = express.Router();

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
  const customerName = String(req.body.customerName || req.body.customer_name || '').trim();
  const phone = loyalty.normalizePhone(req.body.phone);
  const amount = Number(req.body.amount || 0);
  const employeeId = Number(req.body.employeeId || req.body.employee_id || 0) || null;
  const orderId = Number(req.body.orderId || req.body.order_id || 0) || null;

  if (!customerName) {
    return res.status(400).json({ success: false, message: 'Vui lòng nhập tên khách hàng' });
  }
  if (phone.length < 8 || phone.length > 15) {
    return res.status(400).json({ success: false, message: 'Số điện thoại không hợp lệ' });
  }
  if (amount <= 0) {
    return res.status(400).json({ success: false, message: 'Số tiền tích điểm không hợp lệ' });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const customer = await loyalty.ensureCustomerByPhone(connection, {
      customerName,
      phone,
    });

    const currentPoints = Number(customer.points || 0);
    const pointsAdded = loyalty.calculateEarnPoints(amount, currentPoints);
    const totalPoints = currentPoints + pointsAdded;

    if (orderId) {
      const [orders] = await connection.execute(
        `SELECT order_id, payment_status
         FROM orders
         WHERE order_id = ?
         FOR UPDATE`,
        [orderId],
      );
      if (orders.length === 0) {
        await connection.rollback();
        return res.status(404).json({ success: false, message: 'Không tìm thấy đơn hàng' });
      }
      if (!['paid', 'success'].includes(String(orders[0].payment_status || '').toLowerCase())) {
        await connection.rollback();
        return res.status(409).json({
          success: false,
          message: 'Chỉ cộng điểm cho đơn hàng đã thanh toán',
        });
      }
      if (await loyalty.transactionExists(connection, orderId, 'earn')) {
        const [fresh] = await connection.execute(
          'SELECT points FROM users WHERE user_id = ? LIMIT 1',
          [customer.user_id],
        );
        await connection.commit();
        return res.json({
          success: true,
          message: 'Đơn hàng này đã được cộng điểm trước đó',
          data: {
            customerId: customer.user_id,
            customerName,
            phone,
            pointsAdded: 0,
            totalPoints: Number(fresh[0]?.points || totalPoints),
            duplicate: true,
          },
        });
      }
    }

    await connection.execute(
      'UPDATE users SET points = ? WHERE user_id = ?',
      [totalPoints, customer.user_id],
    );
    await connection.execute(
      `INSERT INTO loyalty_transactions (user_id, order_id, points_change, type, note)
       VALUES (?, ?, ?, 'earn', ?)`,
      [
        customer.user_id,
        orderId,
        pointsAdded,
        `POS tích điểm ${amount.toLocaleString('vi-VN')} VND${employeeId ? ` bởi NV ${employeeId}` : ''}`,
      ],
    );
    if (orderId) {
      await loyalty.updateOrderLoyaltyColumns(connection, orderId, {
        points_earned: pointsAdded,
      });
    }

    await connection.commit();
    return res.json({
      success: true,
      message: 'Đã tích điểm khách hàng',
      data: {
        customerId: customer.user_id,
        customerName,
        phone,
        pointsAdded,
        totalPoints,
      },
    });
  } catch (error) {
    await connection.rollback();
    const status = error.status || (error.code === 'ER_DUP_ENTRY' ? 409 : 500);
    return res.status(status).json({
      success: false,
      message: 'Lỗi tích điểm khách hàng',
      error: error.message,
    });
  } finally {
    connection.release();
  }
});

module.exports = router;
