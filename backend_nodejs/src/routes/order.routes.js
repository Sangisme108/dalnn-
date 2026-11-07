const express = require("express");
const pool = require("../config/db");
const { requireAuth, requireRoles, isStaff, canAccessOrder } = require("../middlewares/auth.middleware");
const loyalty = require("../services/loyalty.service");
const billing = require('../services/order-billing.service');
const costing = require('../services/costing.service');

const router = express.Router();
router.use(requireAuth);

router.post('/:id/refunds', requireRoles('admin'), async (req,res) => {
  try {
    const data=await require('../services/refund.service').record(pool,req.user.user_id,billing.quantity(req.params.id),req.body||{});
    res.json({success:true,data});
  } catch(e) { res.status(e.status||(e.code==='ER_DUP_ENTRY'?409:500)).json({success:false,
    message:e.status?e.message:e.code==='ER_DUP_ENTRY'?'Chứng từ hoàn tiền đã được ghi nhận':'Chưa xác định kết quả hoàn tiền. Thử lại cùng UUID.'}); }
});

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

async function getActiveShiftId(connection, employeeId) {
  if (!employeeId) return null;
  const [statusColumns] = await connection.execute(
    `SELECT COUNT(*) AS count
     FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'work_shifts'
       AND COLUMN_NAME = 'status'`,
  );
  const hasShiftStatus = Number(statusColumns[0]?.count || 0) > 0;
  const activeWhere = hasShiftStatus
    ? "end_time IS NULL AND status IN ('active', 'working')"
    : "end_time IS NULL";
  const [rows] = await connection.execute(
    `SELECT shift_id
     FROM work_shifts
     WHERE employee_id = ?
       AND ${activeWhere}
     ORDER BY shift_date DESC, start_time DESC, shift_id DESC
     LIMIT 1`,
    [employeeId],
  );
  return rows[0]?.shift_id || null;
}

async function ordersHasShiftId(connection) {
  const [rows] = await connection.execute(
    `SELECT COUNT(*) AS count
     FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'orders'
       AND COLUMN_NAME = 'shift_id'`,
  );
  return Number(rows[0]?.count || 0) > 0;
}

async function ordersColumns(connection) {
  const [rows] = await connection.execute(
    `SELECT COLUMN_NAME
     FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'orders'`,
  );
  return new Set(rows.map((row) => row.COLUMN_NAME));
}

async function paymentsColumns(connection) {
  const [rows] = await connection.execute(
    `SELECT COLUMN_NAME
     FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'payments'`,
  );
  return new Set(rows.map((row) => row.COLUMN_NAME));
}

function normalizeOrder(row) {
  const orderStatus = row.order_status || row.status;
  const paymentMethod = row.payment_method || row.latest_payment_method || "cash";
  return {
    ...row,
    id: String(row.order_id),
    orderDate: row.created_at,
    totalAmount: Number(row.final_amount),
    customerName: row.customer_name || "Khách lẻ",
    status: orderStatus,
    orderStatus,
    paymentStatus: row.payment_status || row.latest_payment_status,
    paymentMethod,
    transferContent: row.transfer_content || null,
    pointsUsed: Number(row.points_used || 0),
    pointsEarned: Number(row.points_earned || 0),
    pointsDiscount: Number(row.points_discount || 0),
    customerPointsBalance: row.customer_points_balance == null ? null : Number(row.customer_points_balance),
    deliveryMethod: row.delivery_method,
    shippingAddress: row.shipping_address,
    transactionId: row.transaction_id || null,
    paidAt: row.paid_at || null,
  };
}

function normalizeOrderStatusValue(status, orderType) {
  if (!status) return orderType === "online" ? "pending" : "completed";
  if (status === "waiting_confirm") return "pending";
  if (status === "preparing") return "shipping";
  if (status === "Hoàn thành" || status === "hoàn thành") {
    return "completed";
  }
  return status;
}

async function fetchOrder(orderId, executor = pool) {
  const [orders] = await executor.execute(
    `SELECT o.*, cu.full_name AS customer_name, cu.points AS customer_points_balance, eu.full_name AS employee_name,
            pay.method AS latest_payment_method, pay.status AS latest_payment_status
     FROM orders o
     LEFT JOIN users cu ON cu.user_id = o.customer_id
     LEFT JOIN users eu ON eu.user_id = o.employee_id
     ${paymentJoinSql}
     WHERE o.order_id = ?`,
    [orderId],
  );
  if (orders.length === 0) return null;

  const [items] = await executor.execute(
    `SELECT oi.*, p.product_name, p.image_url
     FROM order_items oi
     JOIN products p ON p.product_id = oi.product_id
     WHERE oi.order_id = ?
     ORDER BY oi.order_item_id`,
    [orderId],
  );

  return {
    ...normalizeOrder(orders[0]),
    status: orders[0].order_status || orders[0].status,
    items: items.map(normalizeOrderItem),
  };
}

function normalizeOrderItem(item) {
  return {
    ...item,
    productId: String(item.product_id),
    productName: item.product_name,
    unitPrice: Number(item.price),
    subtotal: Number(item.subtotal),
  };
}

function currentUserId(req) {
  return Number(req.user.user_id);
}


router.get("/", async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT o.*, cu.full_name AS customer_name, eu.full_name AS employee_name,
              pay.method AS latest_payment_method, pay.status AS latest_payment_status
       FROM orders o
       LEFT JOIN users cu ON cu.user_id = o.customer_id
       LEFT JOIN users eu ON eu.user_id = o.employee_id
       ${paymentJoinSql}
       ${isStaff(req.user) ? '' : 'WHERE o.customer_id = ?'}
       ORDER BY o.created_at DESC`,
      isStaff(req.user) ? [] : [currentUserId(req)],
    );
    res.json({ success: true, data: rows.map(normalizeOrder) });
  } catch (error) {
    res
      .status(500)
      .json({
        success: false,
        message: "Lỗi lấy đơn hàng",
        error: error.message,
      });
  }
});

router.get("/online", requireRoles('admin', 'employee'), async (req, res) => {
  try {
    const connection = await pool.getConnection();
    const columns = await ordersColumns(connection);
    connection.release();
    const statusWhere = columns.has("order_status")
      ? `(
           o.order_status IN ('pending', 'waiting_confirm', 'confirmed', 'shipping')
           OR o.status IN ('pending', 'confirmed', 'preparing')
         )`
      : "o.status IN ('pending', 'confirmed', 'preparing')";
    const [rows] = await pool.execute(
      `SELECT o.*, cu.full_name AS customer_name, eu.full_name AS employee_name,
              pay.method AS latest_payment_method, pay.status AS latest_payment_status
       FROM orders o
       LEFT JOIN users cu ON cu.user_id = o.customer_id
       LEFT JOIN users eu ON eu.user_id = o.employee_id
       ${paymentJoinSql}
       WHERE o.order_type IN ('online', 'store_pickup', 'delivery')
         AND ${statusWhere}
       ORDER BY o.created_at DESC, o.order_id DESC`,
    );
    res.json({ success: true, data: rows.map(normalizeOrder) });
  } catch (error) {
    res
      .status(500)
      .json({
        success: false,
        message: "Lỗi lấy đơn online",
        error: error.message,
      });
  }
});

router.get(
  "/pending",
  requireAuth,
  requireRoles("employee", "admin"),
  async (req, res) => {
    try {
      const columns = await ordersColumns(pool);
      const statusWhere = columns.has("order_status")
        ? "COALESCE(o.order_status, o.status, 'pending') IN ('pending', 'waiting_confirm', 'confirmed', 'shipping', 'completed', 'rejected', 'cancelled')"
        : "COALESCE(o.status, 'pending') IN ('pending', 'waiting_confirm', 'confirmed', 'shipping', 'completed', 'rejected', 'cancelled')";

      const [rows] = await pool.execute(
        `SELECT o.*, cu.full_name AS customer_name, eu.full_name AS employee_name,
                pay.method AS latest_payment_method, pay.status AS latest_payment_status
         FROM orders o
         LEFT JOIN users cu ON cu.user_id = o.customer_id
         LEFT JOIN users eu ON eu.user_id = o.employee_id
         ${paymentJoinSql}
         WHERE o.order_type IN ('store_pickup', 'delivery', 'online')
           AND ${statusWhere}
         ORDER BY o.created_at DESC, o.order_id DESC`,
      );

      // Batch item reads instead of two sequential cloud round trips per order.
      const itemsByOrder = new Map();
      const batchSize = 500;
      for (let offset = 0; offset < rows.length; offset += batchSize) {
        const ids = rows.slice(offset, offset + batchSize).map((row) => row.order_id);
        const [items] = await pool.execute(
          `SELECT oi.*, p.product_name, p.image_url
           FROM order_items oi
           JOIN products p ON p.product_id = oi.product_id
           WHERE oi.order_id IN (${ids.map(() => '?').join(',')})
           ORDER BY oi.order_id, oi.order_item_id`,
          ids,
        );
        for (const item of items) {
          const key = String(item.order_id);
          if (!itemsByOrder.has(key)) itemsByOrder.set(key, []);
          itemsByOrder.get(key).push(normalizeOrderItem(item));
        }
      }
      const orders = rows.map((row) => ({
        ...normalizeOrder(row),
        items: itemsByOrder.get(String(row.order_id)) || [],
      }));

      res.json({ success: true, data: orders });
    } catch (error) {
      res.status(500).json({
        success: false,
        message: "Lỗi lấy đơn chờ xác nhận",
        error: error.message,
      });
    }
  },
);

router.put(
  "/:id/confirm",
  requireAuth,
  requireRoles("employee", "admin"),
  async (req, res) => {
    const connection = await pool.getConnection();
    try {
      const employeeId = currentUserId(req);
      await connection.beginTransaction();

      const [orders] = await connection.execute(
        `SELECT *
         FROM orders
         WHERE order_id = ?
         FOR UPDATE`,
        [req.params.id],
      );
      if (orders.length === 0) {
        await connection.rollback();
        return res.status(404).json({
          success: false,
          message: "Không tìm thấy đơn hàng",
        });
      }

      const order = orders[0];
      const currentStatus = normalizeOrderStatusValue(
        order.order_status || order.status,
        order.order_type,
      );
      if (currentStatus !== "pending") {
        await connection.rollback();
        return res.status(409).json({
          success: false,
          message: "Đơn hàng không còn ở trạng thái chờ xác nhận",
        });
      }

      const isDeliveryOrder =
        order.delivery_method === "delivery" || order.order_type === "delivery";
      const nextStatus = isDeliveryOrder ? "shipping" : "completed";
      const columns = await ordersColumns(connection);

      const setParts = ["status = ?"];
      const params = [nextStatus];
      if (columns.has("order_status")) {
        setParts.push("order_status = ?");
        params.push(nextStatus);
      }
      if (columns.has("confirmed_by")) {
        setParts.push("confirmed_by = ?");
        params.push(employeeId || null);
      }
      if (columns.has("confirmed_at")) {
        setParts.push("confirmed_at = NOW()");
      }
      if (columns.has("rejection_reason")) {
        setParts.push("rejection_reason = NULL");
      }
      if (columns.has("employee_id")) {
        setParts.push("employee_id = COALESCE(employee_id, ?)");
        params.push(employeeId || null);
      }
      params.push(req.params.id);

      await connection.execute(
        `UPDATE orders SET ${setParts.join(", ")} WHERE order_id = ?`,
        params,
      );
      const confirmed = await fetchOrder(req.params.id, connection);
      await connection.commit();
      res.json({
        success: true,
        message: "Đã xác nhận đơn hàng",
        data: confirmed,
      });
    } catch (error) {
      await connection.rollback();
      res.status(500).json({
        success: false,
        message: "Lỗi xác nhận đơn hàng",
        error: error.message,
      });
    } finally {
      connection.release();
    }
  },
);

router.put(
  "/:id/reject",
  requireAuth,
  requireRoles("employee", "admin"),
  async (req, res) => {
    const connection = await pool.getConnection();
    try {
      const employeeId = currentUserId(req);
      const reason = String(
        req.body.reason || req.body.rejection_reason || "",
      ).trim();

      await connection.beginTransaction();
      const [orders] = await connection.execute(
        `SELECT *
         FROM orders
         WHERE order_id = ?
         FOR UPDATE`,
        [req.params.id],
      );
      if (orders.length === 0) {
        await connection.rollback();
        return res.status(404).json({
          success: false,
          message: "Không tìm thấy đơn hàng",
        });
      }

      const order = orders[0];
      const currentStatus = normalizeOrderStatusValue(
        order.order_status || order.status,
        order.order_type,
      );
      if (currentStatus !== "pending") {
        await connection.rollback();
        return res.status(409).json({
          success: false,
          message: "Đơn hàng không còn ở trạng thái chờ xác nhận",
        });
      }

      await billing.releaseUnpaidOrder(connection, order);
      const columns = await ordersColumns(connection);
      const setParts = ["status = ?"];
      const params = ["rejected"];
      if (columns.has("order_status")) {
        setParts.push("order_status = ?");
        params.push("rejected");
      }
      if (columns.has("confirmed_by")) {
        setParts.push("confirmed_by = ?");
        params.push(employeeId || null);
      }
      if (columns.has("confirmed_at")) {
        setParts.push("confirmed_at = NOW()");
      }
      if (columns.has("employee_id")) {
        setParts.push("employee_id = COALESCE(employee_id, ?)");
        params.push(employeeId || null);
      }
      if (columns.has("rejection_reason")) {
        setParts.push("rejection_reason = ?");
        params.push(reason || null);
      } else if (columns.has("note")) {
        setParts.push("note = ?");
        params.push(reason || null);
      }
      params.push(req.params.id);

      await connection.execute(
        `UPDATE orders SET ${setParts.join(", ")} WHERE order_id = ?`,
        params,
      );
      const rejected = await fetchOrder(req.params.id, connection);
      await connection.commit();
      res.json({
        success: true,
        message: "Đã từ chối đơn hàng",
        data: rejected,
      });
    } catch (error) {
      await connection.rollback();
      res.status(error.status || 500).json({
        success: false,
        message: error.status ? error.message : "Lỗi từ chối đơn hàng",
        error: error.message,
      });
    } finally {
      connection.release();
    }
  },
);

router.put("/:id/received", requireAuth, async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const customerId = currentUserId(req);
    await connection.beginTransaction();

    const [orders] = await connection.execute(
      `SELECT *
       FROM orders
       WHERE order_id = ?
       FOR UPDATE`,
      [req.params.id],
    );
    if (orders.length === 0) {
      await connection.rollback();
      return res.status(404).json({
        success: false,
        message: "Không tìm thấy đơn hàng",
      });
    }

    const order = orders[0];
    if (Number(order.customer_id) !== Number(customerId)) {
      await connection.rollback();
      return res.status(403).json({
        success: false,
        message: "Bạn chỉ được xác nhận đơn hàng của mình",
      });
    }

    const currentStatus = normalizeOrderStatusValue(
      order.order_status || order.status,
      order.order_type,
    );
    if (currentStatus !== "shipping") {
      await connection.rollback();
      return res.status(409).json({
        success: false,
        message: "Chỉ đơn đang giao mới có thể xác nhận đã nhận hàng",
      });
    }

    const isDeliveryOrder =
      order.delivery_method === "delivery" || order.order_type === "delivery";
    if (!isDeliveryOrder) {
      await connection.rollback();
      return res.status(409).json({
        success: false,
        message: "Chỉ đơn giao tận nhà mới cần xác nhận đã nhận hàng",
      });
    }

    const columns = await ordersColumns(connection);
    const setParts = ["status = ?"];
    const params = ["completed"];
    if (columns.has("order_status")) {
      setParts.push("order_status = ?");
      params.push("completed");
    }
    params.push(req.params.id);

    await connection.execute(
      `UPDATE orders SET ${setParts.join(", ")} WHERE order_id = ?`,
      params,
    );
    const completed = await fetchOrder(req.params.id, connection);
    await connection.commit();
    res.json({
      success: true,
      message: "Đã xác nhận nhận hàng",
      data: completed,
    });
  } catch (error) {
    await connection.rollback();
    res.status(500).json({
      success: false,
      message: "Lỗi xác nhận nhận hàng",
      error: error.message,
    });
  } finally {
    connection.release();
  }
});

router.put("/:id/cancel", requireAuth, async (req, res) => {
  let connection;
  try {
    connection = await pool.getConnection();
    const customerId = currentUserId(req);
    const reason = String(
      req.body.reason || req.body.cancellation_reason || "",
    ).trim();

    if (!reason) {
      return res.status(400).json({
        success: false,
        message: "Vui lòng nhập lý do hủy đơn hàng",
      });
    }
    if (reason.length > 255) {
      return res.status(400).json({
        success: false,
        message: "Lý do hủy không được vượt quá 255 ký tự",
      });
    }

    await connection.beginTransaction();
    const [orders] = await connection.execute(
      `SELECT *
       FROM orders
       WHERE order_id = ?
       FOR UPDATE`,
      [req.params.id],
    );
    if (orders.length === 0) {
      await connection.rollback();
      return res.status(404).json({
        success: false,
        message: "Không tìm thấy đơn hàng",
      });
    }

    const order = orders[0];
    if (Number(order.customer_id) !== Number(customerId)) {
      await connection.rollback();
      return res.status(403).json({
        success: false,
        message: "Bạn chỉ được hủy đơn hàng của mình",
      });
    }

    const currentStatus = normalizeOrderStatusValue(
      order.order_status || order.status,
      order.order_type,
    );
    if (!["pending", "confirmed", "shipping"].includes(currentStatus)) {
      await connection.rollback();
      return res.status(409).json({
        success: false,
        message: "Đơn hàng ở trạng thái hiện tại không thể hủy",
      });
    }

    await billing.releaseUnpaidOrder(connection, order);

    const columns = await ordersColumns(connection);
    const setParts = ["status = ?"];
    const params = ["cancelled"];
    if (columns.has("order_status")) {
      setParts.push("order_status = ?");
      params.push("cancelled");
    }
    if (columns.has("rejection_reason")) {
      setParts.push("rejection_reason = ?");
      params.push(reason);
    } else if (columns.has("note")) {
      setParts.push("note = ?");
      params.push(reason);
    }
    params.push(req.params.id);

    await connection.execute(
      `UPDATE orders SET ${setParts.join(", ")} WHERE order_id = ?`,
      params,
    );
    const cancelled = await fetchOrder(req.params.id, connection);
    await connection.commit();
    res.json({
      success: true,
      message: "Đã hủy đơn hàng",
      data: cancelled,
    });
  } catch (error) {
    if (connection) {
      try {
        await connection.rollback();
      } catch (rollbackError) {
        console.error('Order cancel rollback failed:', rollbackError.code || rollbackError.name);
      }
    }
    const errorCode = error.code || 'ORDER_CANCEL_FAILED';
    console.error('Order cancellation failed:', { orderId: req.params.id, code: errorCode, message: error.message });
    res.status(error.status || 500).json({
      success: false,
      message: error.status ? error.message : `Không xử lý được hủy đơn hàng (${errorCode}).`,
      code: errorCode,
    });
  } finally {
    if (connection) connection.release();
  }
});

router.post("/checkout", requireAuth, async (req, res) => {
  let connection;
  let started = false;
  try {
    const body = req.body || {};
    const customerId = currentUserId(req);
    const deliveryMethod = String(body.delivery_method || body.deliveryMethod || 'pickup').trim();
    const paymentMethod = String(body.payment_method || body.paymentMethod || 'cash').trim();
    const shippingAddress = String(body.shipping_address || body.shippingAddress || '').trim();
    const pickupTimeRaw = body.pickup_time || body.pickupTime;
    const pickupTime = pickupTimeRaw ? new Date(pickupTimeRaw) : null;
    if (!['pickup', 'delivery'].includes(deliveryMethod)) billing.fail('Hình thức nhận hàng không hợp lệ');
    if (deliveryMethod === 'delivery' && !shippingAddress) billing.fail('Vui lòng nhập địa chỉ giao hàng');
    if (deliveryMethod === 'pickup' && (!pickupTime || Number.isNaN(pickupTime.getTime()) || pickupTime <= new Date())) billing.fail('Vui lòng chọn thời gian nhận tại quầy hợp lệ');
    if (!['cash', 'ewallet', 'vnpay', 'bank_transfer'].includes(paymentMethod)) billing.fail('Phương thức thanh toán không hợp lệ');
    connection = await pool.getConnection();
    await connection.beginTransaction();
    started = true;
    const [carts] = await connection.execute('SELECT cart_id FROM carts WHERE user_id = ? ORDER BY cart_id DESC LIMIT 1 FOR UPDATE', [customerId]);
    if (!carts[0]) billing.fail('Giỏ hàng đang trống');
    const cartId = carts[0].cart_id;
    const [items] = await connection.execute('SELECT product_id, quantity FROM cart_items WHERE cart_id = ? FOR UPDATE', [cartId]);
    const { normalizedItems, totalMinor, total } = await billing.priceItems(connection, items);
    const pointsRequested = body.points_to_use ?? body.points_used ?? 0;
    let availablePoints = 0;
    if (Number(pointsRequested) !== 0) {
      const [customers] = await connection.execute("SELECT u.user_id, u.points FROM users u JOIN roles r ON r.role_id = u.role_id WHERE u.user_id = ? AND r.role_name = 'customer' AND u.status = 'active' FOR UPDATE", [customerId]);
      if (!customers[0]) billing.fail('Tài khoản không được dùng điểm', 403);
      availablePoints = Number(customers[0].points || 0);
    }
    const { voucher, discountMinor } = await billing.applyVoucher(connection, {
      totalMinor, voucherId: body.voucher_id ?? body.voucherId, voucherCode: body.voucher_code ?? body.voucherCode, customerId,
    });
    const manualMinor = billing.manualDiscount(req.user, body, totalMinor, discountMinor);
    const discountAmount = (discountMinor + manualMinor) / 100;
    const amountAfterVoucher = (totalMinor - discountMinor - manualMinor) / 100;
    const { pointsUsed, pointsDiscount } = loyalty.validateRedeem({ pointsToUse: pointsRequested, availablePoints, amountAfterVoucher });
    const finalAmount = (totalMinor - discountMinor - manualMinor - billing.moneyMinor(pointsDiscount)) / 100;
    const paymentStatus = finalAmount === 0 ? 'paid' : 'pending';
    const columns = await ordersColumns(connection);
    if (pointsUsed && !['points_used', 'points_earned', 'points_discount'].every((column) => columns.has(column))) billing.fail('Database chưa có đủ cột điểm. Cần kiểm tra migration hiện có', 409);
    const effectiveNote = deliveryMethod === 'pickup' && !columns.has('pickup_time')
      ? [body.note, 'Thời gian nhận tại quầy: ' + pickupTime.toLocaleString('vi-VN')].filter(Boolean).join('\n') : body.note || null;
    const values = {
      customer_id: customerId, employee_id: null, voucher_id: voucher?.voucher_id || null,
      order_type: deliveryMethod === 'delivery' ? 'delivery' : 'store_pickup',
      total_amount: total, discount_amount: discountAmount, final_amount: finalAmount,
      status: 'pending', payment_status: paymentStatus, shipping_address: deliveryMethod === 'delivery' ? shippingAddress : null,
      note: effectiveNote,
    };
    const optional = { reporting_version: 1, voucher_discount: discountMinor / 100, manual_discount: manualMinor / 100, shift_id: null, delivery_method: deliveryMethod, payment_method: paymentMethod, order_status: 'pending',
      pickup_time: deliveryMethod === 'pickup' ? pickupTime : null, points_used: pointsUsed, points_earned: 0, points_discount: pointsDiscount };
    for (const [key, value] of Object.entries(optional)) if (columns.has(key)) values[key] = value;
    const [created] = await connection.execute('INSERT INTO orders (' + Object.keys(values).join(', ') + ') VALUES (' + Object.keys(values).map(() => '?').join(', ') + ')', Object.values(values));
    const orderId = created.insertId;
    const transferContent = paymentMethod === 'bank_transfer' ? 'DH' + orderId : null;
    if (transferContent && columns.has('transfer_content')) await connection.execute('UPDATE orders SET transfer_content = ? WHERE order_id = ?', [transferContent, orderId]);
    await loyalty.reserveOrderPoints(connection, orderId, customerId, pointsUsed, amountAfterVoucher);
    await billing.subtractStock(connection, normalizedItems);
    await costing.saveLines(connection, orderId, normalizedItems, (totalMinor - billing.moneyMinor(finalAmount)) / 100);
    await connection.execute('INSERT INTO payments (order_id, method, amount, status, qr_content, paid_at) VALUES (?, ?, ?, ?, ?, ?)',
      [orderId, paymentMethod, finalAmount, paymentStatus, transferContent, paymentStatus === 'paid' ? new Date() : null]);
    if (paymentStatus === 'paid') await loyalty.finalizePaidOrderLoyalty(connection, orderId);
    await connection.execute('DELETE FROM cart_items WHERE cart_id = ?', [cartId]);
    await costing.recognize(connection, orderId);
    const order = await fetchOrder(orderId, connection);
    await connection.commit();
    started = false;
    res.status(201).json({ success: true, message: 'Đã tạo đơn hàng online', data: {
      ...order, deliveryMethod, voucherCode: voucher?.code || null, discountAmount, finalAmount,
      fakeQrContent: null, transferContent, requiresVnpayPayment: paymentMethod === 'vnpay' && paymentStatus !== 'paid',
    } });
  } catch (error) {
    if (connection && started) { try { await connection.rollback(); } catch (_) {} }
    res.status(error.status || (['ER_LOCK_DEADLOCK', 'ER_LOCK_WAIT_TIMEOUT'].includes(error.code) ? 409 : 500)).json({
      success: false, message: error.status ? error.message : 'Chưa tạo được đơn hàng online. Vui lòng kiểm tra lại trước khi thử lại.',
    });
  } finally { if (connection) connection.release(); }
});

async function fetchHistory(req, res) {
  try {
    const customerId = Number(req.params.customerId || (!isStaff(req.user) ? currentUserId(req) : 0));
    if (!isStaff(req.user) && customerId !== currentUserId(req)) {
      return res.status(403).json({ success: false, message: 'Bạn chỉ được xem lịch sử mua hàng của mình' });
    }
    const params = [];
    let customerWhere = "";
    if (customerId) {
      customerWhere = "AND o.customer_id = ?";
      params.push(customerId);
    }

    const [rows] = await pool.execute(
      `SELECT o.order_id
       FROM orders o
       WHERE o.status IN ('completed', 'Hoàn thành', 'hoàn thành')
         ${customerWhere}
       ORDER BY o.created_at DESC`,
      params,
    );
    const orders = [];
    for (const row of rows) {
      const order = await fetchOrder(row.order_id);
      if (order) orders.push(order);
    }
    res.json({ success: true, data: orders });
  } catch (error) {
    res
      .status(500)
      .json({
        success: false,
        message: "Lỗi lấy lịch sử mua hàng",
        error: error.message,
      });
  }
}

router.get("/history", fetchHistory);
router.get("/history/:customerId", fetchHistory);

router.get("/status/:orderCode", async (req, res) => {
  try {
    const rawCode = String(req.params.orderCode || "").trim().toUpperCase();
    const normalizedCode = rawCode.replace(/[^A-Z0-9]/g, "");
    const orderIdFromCode = Number(normalizedCode.replace(/^DH/, ""));
    if (!normalizedCode) {
      return res.status(400).json({ success: false, message: "Thiếu mã đơn hàng" });
    }

    const connection = await pool.getConnection();
    const columns = await ordersColumns(connection);
    connection.release();
    const where = columns.has("transfer_content")
      ? "(UPPER(transfer_content) = ? OR order_id = ?)"
      : "order_id = ?";
    const params = columns.has("transfer_content")
      ? [normalizedCode, orderIdFromCode || 0]
      : [orderIdFromCode || 0];
    const [rows] = await pool.execute(
      `SELECT order_id
       FROM orders
       WHERE ${where}
       ORDER BY created_at DESC, order_id DESC
       LIMIT 1`,
      params,
    );
    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: "Không tìm thấy đơn hàng" });
    }

    const order = await fetchOrder(rows[0].order_id);
    if (!canAccessOrder(req.user, order)) {
      return res.status(403).json({ success: false, message: 'Bạn không có quyền xem đơn hàng này' });
    }
    const paymentStatus = String(order.paymentStatus || "pending").toLowerCase();
    return res.json({
      success: true,
      data: {
        orderCode: order.transferContent || `DH${order.id}`,
        orderId: Number(order.id),
        paymentStatus,
        orderStatus: order.orderStatus || order.status,
        status: order.status,
        totalAmount: order.totalAmount,
        paidAt: order.paidAt || null,
        transactionId: order.transactionId || null,
        isPaid: ["paid", "success"].includes(paymentStatus),
        isFailed: paymentStatus === "failed",
        isPending: !["paid", "success", "failed"].includes(paymentStatus),
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Lỗi kiểm tra trạng thái đơn hàng",
      error: error.message,
    });
  }
});

router.get("/:id/payment-status", requireAuth, async (req, res) => {
  try {
    const userId = currentUserId(req);
    const orderId = Number(req.params.id);
    if (!userId) {
      return res.status(401).json({ success: false, message: "Vui lòng đăng nhập" });
    }

    const order = await fetchOrder(orderId);
    if (!order) {
      return res.status(404).json({ success: false, message: "Không tìm thấy đơn hàng" });
    }

    const [rawRows] = await pool.execute(
      `SELECT o.customer_id, o.employee_id, r.role_name
       FROM orders o
       LEFT JOIN users u ON u.user_id = ?
       LEFT JOIN roles r ON r.role_id = u.role_id
       WHERE o.order_id = ?
       LIMIT 1`,
      [userId, orderId],
    );
    const raw = rawRows[0] || {};
    const customerId = Number(raw.customer_id || 0);
    const employeeId = Number(raw.employee_id || 0);
    if (!canAccessOrder(req.user, { customer_id: customerId, employee_id: employeeId })) {
      return res.status(403).json({ success: false, message: "Không có quyền xem đơn này" });
    }

    const [paymentRows] = await pool.execute(
      `SELECT method, transaction_id, paid_at
       FROM payments
       WHERE order_id = ?
       ORDER BY payment_id DESC
       LIMIT 1`,
      [orderId],
    );
    const latestPayment = paymentRows[0] || {};

    const paymentStatus = String(order.paymentStatus || "pending").toLowerCase();
    res.json({
      success: true,
      data: {
        orderId,
        paymentStatus,
        orderStatus: order.orderStatus || order.status,
        paymentMethod: order.paymentMethod,
        transactionId: order.transactionId || latestPayment.transaction_id || null,
        paidAt: order.paidAt || latestPayment.paid_at || null,
        transferContent: order.transferContent || null,
        totalAmount: order.totalAmount,
        pointsUsed: order.pointsUsed || 0,
        pointsEarned: order.pointsEarned || 0,
        pointsDiscount: order.pointsDiscount || 0,
        customerPointsBalance: order.customerPointsBalance,
        isPaid: ["paid", "success"].includes(paymentStatus),
        isFailed: paymentStatus === "failed",
        isPending: !["paid", "success", "failed"].includes(paymentStatus),
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Lỗi kiểm tra trạng thái thanh toán",
      error: error.message,
    });
  }
});

router.get("/:id", async (req, res) => {
  try {
    const order = await fetchOrder(req.params.id);
    if (!order) {
      return res
        .status(404)
        .json({ success: false, message: "Không tìm thấy đơn hàng" });
    }
    if (!canAccessOrder(req.user, order)) {
      return res.status(403).json({ success: false, message: 'Bạn không có quyền xem đơn hàng này' });
    }
    res.json({ success: true, data: order });
  } catch (error) {
    res
      .status(500)
      .json({
        success: false,
        message: "Lỗi lấy đơn hàng",
        error: error.message,
      });
  }
});

router.patch("/:id/status", requireRoles('admin', 'employee'), async (req, res) => {
  let connection;
  try {
    const status = normalizeOrderStatusValue(String(req.body.status || '').trim(), 'online');
    if (!['pending', 'confirmed', 'rejected', 'shipping', 'completed', 'cancelled'].includes(status)) billing.fail('Trạng thái đơn hàng không hợp lệ');
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [rows] = await connection.execute('SELECT * FROM orders WHERE order_id = ? FOR UPDATE', [req.params.id]);
    const current = rows[0];
    if (!current) billing.fail('Không tìm thấy đơn hàng', 404);
    const oldStatus = normalizeOrderStatusValue(current.order_status || current.status, current.order_type);
    if (oldStatus !== status && ['completed', 'rejected', 'cancelled'].includes(oldStatus)) billing.fail('Không được mở lại đơn đã kết thúc', 409);
    if (oldStatus !== status && ['rejected', 'cancelled'].includes(status)) await billing.releaseUnpaidOrder(connection, current);
    const columns = await ordersColumns(connection);
    const setParts = ['status = ?'];
    const params = [status];
    if (columns.has('order_status')) { setParts.push('order_status = ?'); params.push(status); }
    if (['confirmed', 'rejected'].includes(status) && columns.has('confirmed_by')) { setParts.push('confirmed_by = COALESCE(confirmed_by, ?)'); params.push(currentUserId(req)); }
    if (['confirmed', 'rejected'].includes(status) && columns.has('confirmed_at')) setParts.push('confirmed_at = COALESCE(confirmed_at, NOW())');
    params.push(req.params.id);
    await connection.execute('UPDATE orders SET ' + setParts.join(', ') + ' WHERE order_id = ?', params);
    await costing.recognize(connection, req.params.id);
    const order = await fetchOrder(req.params.id, connection);
    await connection.commit();
    res.json({ success: true, message: 'Đã cập nhật trạng thái đơn hàng', data: order });
  } catch (error) {
    if (connection) { try { await connection.rollback(); } catch (_) {} }
    res.status(error.status || 500).json({ success: false, message: error.status ? error.message : 'Chưa cập nhật được trạng thái đơn hàng' });
  } finally { if (connection) connection.release(); }
});

router.post("/", requireRoles('admin', 'employee'), async (req, res) => {
  let connection;
  let started = false;
  try {
    const body = req.body || {};
    const employeeId = currentUserId(req);
    const paymentMethod = String(body.payment_method || 'cash').toLowerCase();
    if (!['cash', 'bank_transfer', 'vnpay', 'card', 'momo', 'ewallet'].includes(paymentMethod)) billing.fail('Phương thức thanh toán không hợp lệ');
    if (body.order_type && body.order_type !== 'offline') billing.fail('Đơn online phải tạo bằng luồng checkout giỏ hàng');
    connection = await pool.getConnection();
    await connection.beginTransaction();
    started = true;

    const { normalizedItems, totalMinor, total } = await billing.priceItems(connection, body.items);
    let customer = null;
    if (loyalty.normalizePhone(body.customer_phone)) {
      customer = await loyalty.ensureCustomerByPhone(connection, {
        customerName: body.customer_name || 'Khách hàng', phone: body.customer_phone,
      });
    } else if (body.customer_id != null) {
      const [customers] = await connection.execute(
        "SELECT u.user_id, u.points, u.full_name FROM users u JOIN roles r ON r.role_id = u.role_id WHERE u.user_id = ? AND r.role_name = 'customer' AND u.status = 'active' FOR UPDATE",
        [billing.quantity(body.customer_id, 'Mã khách hàng')],
      );
      customer = customers[0];
      if (!customer) billing.fail('Khách hàng không hợp lệ', 409);
    }
    const { voucher, discountMinor } = await billing.applyVoucher(connection, {
      totalMinor, voucherId: body.voucher_id ?? body.voucherId, voucherCode: body.voucher_code ?? body.voucherCode, customerId: customer?.user_id,
    });
    const manualMinor = billing.manualDiscount(req.user, body, totalMinor, discountMinor);
    const discountAmount = (discountMinor + manualMinor) / 100;
    const amountAfterVoucher = (totalMinor - discountMinor - manualMinor) / 100;
    const pointsRequested = body.points_to_use ?? body.points_used ?? 0;
    if (!customer && (Number(pointsRequested) !== 0 || body.use_points === true || body.use_points === 'true')) billing.fail('Vui lòng tra khách hàng trước khi dùng điểm');
    const { pointsUsed, pointsDiscount } = loyalty.validateRedeem({
      pointsToUse: pointsRequested, availablePoints: Number(customer?.points || 0), amountAfterVoucher,
    });
    const finalAmount = (totalMinor - discountMinor - manualMinor - billing.moneyMinor(pointsDiscount)) / 100;
    const paid = paymentMethod === 'cash' || finalAmount === 0;
    if (paymentMethod === 'cash' && body.expected_final_amount != null && billing.moneyMinor(body.expected_final_amount) !== billing.moneyMinor(finalAmount)) billing.fail('Giá hoặc ưu đãi đã thay đổi. Vui lòng cập nhật giỏ hàng và xác nhận lại số tiền thu', 409);
    const paymentStatus = paid ? 'paid' : 'pending';
    const orderStatus = paid ? 'completed' : 'pending';
    const columns = await ordersColumns(connection);
    if (pointsUsed && !['points_used', 'points_earned', 'points_discount'].every((column) => columns.has(column))) billing.fail('Database chưa có đủ cột điểm. Cần kiểm tra migration hiện có trước khi sử dụng điểm', 409);
    const shiftId = columns.has('shift_id') ? await getActiveShiftId(connection, employeeId) : null;
    const values = {
      customer_id: customer?.user_id || null, employee_id: employeeId, voucher_id: voucher?.voucher_id || null,
      order_type: 'offline', total_amount: total, discount_amount: discountAmount, final_amount: finalAmount,
      status: orderStatus, payment_status: paymentStatus, shipping_address: null,
      note: [body.note, manualMinor ? '[Owner #' + employeeId + '] Giảm thủ công: ' + manualMinor / 100 + ' VND' : null].filter(Boolean).join('\n') || null,
    };
    const optional = { reporting_version: 1, voucher_discount: discountMinor / 100, manual_discount: manualMinor / 100, shift_id: shiftId, payment_method: paymentMethod, order_status: orderStatus,
      points_used: pointsUsed, points_earned: 0, points_discount: pointsDiscount,
      paid_at: paid ? new Date() : null, transaction_id: paid ? 'POS_' + require('node:crypto').randomUUID() : null,
    };
    for (const [key, value] of Object.entries(optional)) if (columns.has(key)) values[key] = value;
    const [created] = await connection.execute(
      'INSERT INTO orders (' + Object.keys(values).join(', ') + ') VALUES (' + Object.keys(values).map(() => '?').join(', ') + ')',
      Object.values(values),
    );
    const orderId = created.insertId;
    const transferContent = paymentMethod === 'bank_transfer' ? 'DH' + orderId : null;
    if (transferContent && columns.has('transfer_content')) await connection.execute('UPDATE orders SET transfer_content = ? WHERE order_id = ?', [transferContent, orderId]);
    await loyalty.reserveOrderPoints(connection, orderId, customer?.user_id, pointsUsed, amountAfterVoucher);
    await billing.subtractStock(connection, normalizedItems);
    await costing.saveLines(connection, orderId, normalizedItems, (totalMinor - billing.moneyMinor(finalAmount)) / 100);
    const paymentColumns = await paymentsColumns(connection);
    const payment = { order_id: orderId, method: paymentMethod, amount: finalAmount, status: paymentStatus, paid_at: paid ? new Date() : null };
    if (paymentColumns.has('transaction_id')) payment.transaction_id = optional.transaction_id;
    if (paymentColumns.has('qr_content')) payment.qr_content = transferContent;
    await connection.execute(
      'INSERT INTO payments (' + Object.keys(payment).join(', ') + ') VALUES (' + Object.keys(payment).map(() => '?').join(', ') + ')', Object.values(payment),
    );
    if (paid) await loyalty.finalizePaidOrderLoyalty(connection, orderId);
    await costing.recognize(connection, orderId);
    const order = await fetchOrder(orderId, connection);
    await connection.commit();
    started = false;
    res.status(201).json({ success: true, message: 'Đã tạo đơn hàng', data: order });
  } catch (error) {
    if (connection && started) { try { await connection.rollback(); } catch (_) {} }
    res.status(error.status || (['ER_LOCK_DEADLOCK', 'ER_LOCK_WAIT_TIMEOUT'].includes(error.code) ? 409 : 500)).json({
      success: false, message: error.status ? error.message : 'Chưa tạo được đơn hàng. Vui lòng kiểm tra lại trước khi thử lại.',
    });
  } finally { if (connection) connection.release(); }
});

module.exports = router;
