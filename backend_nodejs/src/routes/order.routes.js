const express = require("express");
const pool = require("../config/db");
const { requireAuth, requireRoles } = require("../middlewares/auth.middleware");
const loyalty = require("../services/loyalty.service");

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

async function fetchOrder(orderId) {
  const [orders] = await pool.execute(
    `SELECT o.*, cu.full_name AS customer_name, eu.full_name AS employee_name,
            pay.method AS latest_payment_method, pay.status AS latest_payment_status
     FROM orders o
     LEFT JOIN users cu ON cu.user_id = o.customer_id
     LEFT JOIN users eu ON eu.user_id = o.employee_id
     ${paymentJoinSql}
     WHERE o.order_id = ?`,
    [orderId],
  );
  if (orders.length === 0) return null;

  const [items] = await pool.execute(
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
    items: items.map((item) => ({
      ...item,
      productId: String(item.product_id),
      productName: item.product_name,
      unitPrice: Number(item.price),
      subtotal: Number(item.subtotal),
    })),
  };
}

function currentUserId(req) {
  return Number(req.user?.id || req.user?.user_id || req.get("x-user-id"));
}

function calculateVoucherDiscount(voucher, total) {
  let discountAmount = 0;
  if (voucher.discount_type === "fixed") {
    discountAmount = Number(voucher.discount_value);
  } else if (voucher.discount_type === "percent") {
    discountAmount = total * (Number(voucher.discount_value) / 100);
    if (voucher.max_discount && discountAmount > Number(voucher.max_discount)) {
      discountAmount = Number(voucher.max_discount);
    }
  }
  return Math.min(discountAmount, total);
}

async function applyCheckoutVoucher(connection, userId, total, voucherId, voucherCode) {
  if (!voucherId && !voucherCode) {
    return { voucher: null, discountAmount: 0 };
  }

  const where = voucherId ? "voucher_id = ?" : "code = ?";
  const value = voucherId || voucherCode;
  const [vouchers] = await connection.execute(
    `SELECT *
     FROM vouchers
     WHERE ${where}
       AND status = 'active'
     FOR UPDATE`,
    [value],
  );

  if (vouchers.length === 0) {
    throw new Error("Mã voucher không tồn tại");
  }

  const voucher = vouchers[0];
  if (voucher.expiry_date && new Date(voucher.expiry_date) < new Date()) {
    throw new Error("Voucher đã hết hạn");
  }
  if (voucher.usage_limit && voucher.used_count >= voucher.usage_limit) {
    throw new Error("Voucher đã hết lượt dùng");
  }
  if (total < Number(voucher.min_order_amount || 0)) {
    throw new Error(`Đơn hàng phải tối thiểu ${Number(voucher.min_order_amount).toLocaleString("vi-VN")} VND`);
  }

  const discountAmount = calculateVoucherDiscount(voucher, total);
  await connection.execute(
    "UPDATE vouchers SET used_count = used_count + 1 WHERE voucher_id = ?",
    [voucher.voucher_id],
  );
  await connection.execute(
    `INSERT INTO user_vouchers (user_id, voucher_id, used_count, last_used_at)
     VALUES (?, ?, 1, NOW())
     ON DUPLICATE KEY UPDATE
       used_count = used_count + 1,
       last_used_at = NOW()`,
    [userId, voucher.voucher_id],
  );

  return { voucher, discountAmount };
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
       ORDER BY o.created_at DESC`,
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

router.get("/online", async (req, res) => {
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
      const connection = await pool.getConnection();
      const columns = await ordersColumns(connection);
      connection.release();
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

      const orders = [];
      for (const row of rows) {
        const order = await fetchOrder(row.order_id);
        if (order) orders.push(order);
      }

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
      await connection.commit();

      const confirmed = await fetchOrder(req.params.id);
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
      await connection.commit();

      const rejected = await fetchOrder(req.params.id);
      res.json({
        success: true,
        message: "Đã từ chối đơn hàng",
        data: rejected,
      });
    } catch (error) {
      await connection.rollback();
      res.status(500).json({
        success: false,
        message: "Lỗi từ chối đơn hàng",
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
    await connection.commit();

    const completed = await fetchOrder(req.params.id);
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
  const connection = await pool.getConnection();
  try {
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

    const [items] = await connection.execute(
      `SELECT product_id, quantity
       FROM order_items
       WHERE order_id = ?
       FOR UPDATE`,
      [req.params.id],
    );
    for (const item of items) {
      await connection.execute(
        "UPDATE products SET stock = stock + ? WHERE product_id = ?",
        [Number(item.quantity), item.product_id],
      );
    }

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
    await connection.commit();

    const cancelled = await fetchOrder(req.params.id);
    res.json({
      success: true,
      message: "Đã hủy đơn hàng",
      data: cancelled,
    });
  } catch (error) {
    await connection.rollback();
    res.status(500).json({
      success: false,
      message: "Lỗi hủy đơn hàng",
      error: error.message,
    });
  } finally {
    connection.release();
  }
});

router.post("/checkout", requireAuth, async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const customerId = currentUserId(req);
    const deliveryMethod = String(req.body.delivery_method || req.body.deliveryMethod || "pickup").trim();
    const paymentMethod = String(req.body.payment_method || req.body.paymentMethod || "cash").trim();
    const shippingAddress = String(req.body.shipping_address || req.body.shippingAddress || "").trim();
    const pickupTimeRaw = req.body.pickup_time || req.body.pickupTime;
    const pickupTime = pickupTimeRaw ? new Date(pickupTimeRaw) : null;
    const note = req.body.note ? String(req.body.note).trim() : null;
    const voucherId = Number(req.body.voucher_id || req.body.voucherId) || null;
    const voucherCode = req.body.voucher_code || req.body.voucherCode
      ? String(req.body.voucher_code || req.body.voucherCode).trim().toUpperCase()
      : null;

    if (!customerId) {
      return res.status(401).json({ success: false, message: "Vui lòng đăng nhập" });
    }
    if (!["pickup", "delivery"].includes(deliveryMethod)) {
      return res.status(400).json({ success: false, message: "Hình thức nhận hàng không hợp lệ" });
    }
    if (deliveryMethod === "delivery" && !shippingAddress) {
      return res.status(400).json({ success: false, message: "Vui lòng nhập địa chỉ giao hàng" });
    }
    if (
      deliveryMethod === "pickup" &&
      (!pickupTime || Number.isNaN(pickupTime.getTime()) || pickupTime <= new Date())
    ) {
      return res.status(400).json({
        success: false,
        message: "Vui lòng chọn thời gian nhận tại quầy hợp lệ",
      });
    }
    if (!["cash", "ewallet", "vnpay", "bank_transfer"].includes(paymentMethod)) {
      return res.status(400).json({ success: false, message: "Phương thức thanh toán không hợp lệ" });
    }

    await connection.beginTransaction();

    const [carts] = await connection.execute(
      "SELECT cart_id FROM carts WHERE user_id = ? ORDER BY cart_id DESC LIMIT 1 FOR UPDATE",
      [customerId],
    );
    if (carts.length === 0) {
      await connection.rollback();
      return res.status(400).json({ success: false, message: "Giỏ hàng đang trống" });
    }

    const cartId = carts[0].cart_id;
    const [cartItems] = await connection.execute(
      `SELECT ci.product_id, ci.quantity, p.product_name, p.price, p.stock
       FROM cart_items ci
       JOIN products p ON p.product_id = ci.product_id
       WHERE ci.cart_id = ?
       FOR UPDATE`,
      [cartId],
    );
    if (cartItems.length === 0) {
      await connection.rollback();
      return res.status(400).json({ success: false, message: "Giỏ hàng đang trống" });
    }

    let total = 0;
    const normalizedItems = [];
    for (const item of cartItems) {
      const quantity = Number(item.quantity);
      if (quantity <= 0) continue;
      if (Number(item.stock) < quantity) {
        throw new Error(`Không đủ tồn kho cho ${item.product_name}`);
      }
      const price = Number(item.price);
      const subtotal = price * quantity;
      total += subtotal;
      normalizedItems.push({
        productId: Number(item.product_id),
        quantity,
        price,
        subtotal,
      });
    }

    if (normalizedItems.length === 0) {
      await connection.rollback();
      return res.status(400).json({ success: false, message: "Giỏ hàng đang trống" });
    }

    const { voucher, discountAmount } = await applyCheckoutVoucher(
      connection,
      customerId,
      total,
      voucherId,
      voucherCode,
    );
    const finalAmount = total - discountAmount;
    const paymentStatus = paymentMethod === "ewallet" ? "paid" : "pending";
    // vnpay: pending until IPN/return confirms; cash: pending until pickup/delivery settlement
    const orderStatus = "pending";
    const columns = await ordersColumns(connection);

    const insertColumns = [];
    const insertParams = [];
    const addColumn = (column, value) => {
      insertColumns.push(column);
      insertParams.push(value);
    };

    addColumn("customer_id", customerId);
    addColumn("employee_id", null);
    if (columns.has("shift_id")) addColumn("shift_id", null);
    addColumn("voucher_id", voucher ? voucher.voucher_id : null);
    addColumn("order_type", deliveryMethod === "delivery" ? "delivery" : "store_pickup");
    if (columns.has("delivery_method")) addColumn("delivery_method", deliveryMethod);
    addColumn("total_amount", total);
    addColumn("discount_amount", discountAmount);
    addColumn("final_amount", finalAmount);
    if (columns.has("payment_method")) addColumn("payment_method", paymentMethod);
    addColumn("status", orderStatus);
    addColumn("payment_status", paymentStatus);
    if (columns.has("order_status")) addColumn("order_status", orderStatus);
    addColumn("shipping_address", deliveryMethod === "delivery" ? shippingAddress : null);
    if (columns.has("pickup_time")) {
      addColumn("pickup_time", deliveryMethod === "pickup" ? pickupTime : null);
    }
    const effectiveNote =
      deliveryMethod === "pickup" && !columns.has("pickup_time")
        ? `${note ? `${note}\n` : ""}Thời gian nhận tại quầy: ${pickupTime.toLocaleString("vi-VN")}`
        : note;
    addColumn("note", effectiveNote);

    const insertValues = insertColumns.map(() => "?").join(", ");
    const [orderResult] = await connection.execute(
      `INSERT INTO orders (${insertColumns.join(", ")}) VALUES (${insertValues})`,
      insertParams,
    );

    const generatedTransferContent =
      paymentMethod === "bank_transfer" ? `DH${orderResult.insertId}` : null;
    if (generatedTransferContent && columns.has("transfer_content")) {
      await connection.execute(
        "UPDATE orders SET transfer_content = ? WHERE order_id = ?",
        [generatedTransferContent, orderResult.insertId],
      );
    }

    for (const item of normalizedItems) {
      await connection.execute(
        `INSERT INTO order_items (order_id, product_id, quantity, price, subtotal)
         VALUES (?, ?, ?, ?, ?)`,
        [orderResult.insertId, item.productId, item.quantity, item.price, item.subtotal],
      );
      await connection.execute(
        "UPDATE products SET stock = stock - ? WHERE product_id = ?",
        [item.quantity, item.productId],
      );
    }

    await connection.execute(
      "INSERT INTO payments (order_id, method, amount, status, qr_content, paid_at) VALUES (?, ?, ?, ?, ?, ?)",
      [
        orderResult.insertId,
        paymentMethod,
        finalAmount,
        paymentStatus,
        paymentMethod === "ewallet"
          ? `FAKE_QR_ORDER_${orderResult.insertId}_${Math.round(finalAmount)}`
          : generatedTransferContent,
        paymentStatus === "paid" ? new Date() : null,
      ],
    );

    await connection.execute("DELETE FROM cart_items WHERE cart_id = ?", [cartId]);

    await connection.commit();
    const order = await fetchOrder(orderResult.insertId);
    res.status(201).json({
      success: true,
      message: "Đã tạo đơn hàng online",
      data: {
        ...order,
        deliveryMethod,
        voucherCode: voucher?.code || null,
        discountAmount,
        finalAmount,
        fakeQrContent:
          paymentMethod === "ewallet"
            ? `FAKE_QR_ORDER_${orderResult.insertId}_${Math.round(finalAmount)}`
            : null,
        transferContent: generatedTransferContent,
        requiresVnpayPayment: paymentMethod === "vnpay",
      },
    });
  } catch (error) {
    await connection.rollback();
    const isBusinessError =
      error.message &&
      (error.message.startsWith("Không đủ tồn kho") ||
        error.message.includes("Giỏ hàng đang trống") ||
        error.message.includes("không hợp lệ"));
    res.status(isBusinessError ? 400 : 500).json({
      success: false,
      message: isBusinessError ? error.message : "Lỗi checkout đơn hàng online",
      error: error.message,
    });
  } finally {
    connection.release();
  }
});

async function fetchHistory(req, res) {
  try {
    const customerId = Number(req.params.customerId || req.get("x-user-id"));
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
    const roleName = String(raw.role_name || "");
    if (customerId !== userId && employeeId !== userId && roleName !== "admin") {
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

router.patch("/:id/status", async (req, res) => {
  try {
    const status = String(req.body.status || "").trim();
    const allowed = [
      "waiting_confirm",
      "pending",
      "confirmed",
      "rejected",
      "shipping",
      "preparing",
      "completed",
      "cancelled",
    ];
    if (!allowed.includes(status)) {
      return res
        .status(400)
        .json({ success: false, message: "Trạng thái đơn hàng không hợp lệ" });
    }

    const orderStatus = normalizeOrderStatusValue(status, "online");
    const employeeId = Number(req.get("x-user-id")) || null;
    const connection = await pool.getConnection();
    const columns = await ordersColumns(connection);
    connection.release();

    const setParts = ["status = ?"];
    const params = [orderStatus];
    if (columns.has("order_status")) {
      setParts.push("order_status = ?");
      params.push(orderStatus);
    }
    if (["confirmed", "rejected"].includes(orderStatus) && columns.has("confirmed_by")) {
      setParts.push("confirmed_by = COALESCE(confirmed_by, ?)");
      params.push(employeeId);
    }
    if (["confirmed", "rejected"].includes(orderStatus) && columns.has("confirmed_at")) {
      setParts.push("confirmed_at = COALESCE(confirmed_at, NOW())");
    }
    params.push(req.params.id);

    const [result] = await pool.execute(
      `UPDATE orders SET ${setParts.join(", ")} WHERE order_id = ?`,
      params,
    );
    if (result.affectedRows === 0) {
      return res
        .status(404)
        .json({ success: false, message: "Không tìm thấy đơn hàng" });
    }

    const order = await fetchOrder(req.params.id);
    res.json({
      success: true,
      message: "Đã cập nhật trạng thái đơn hàng",
      data: order,
    });
  } catch (error) {
    res
      .status(500)
      .json({
        success: false,
        message: "Lỗi cập nhật trạng thái đơn hàng",
        error: error.message,
      });
  }
});

router.post("/", async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const {
      customer_id,
      employee_id,
      order_type = "offline",
      status,
      order_status,
      payment_status,
      shipping_address,
      note,
      payment_method = "cash",
      items,
      voucher_id,
      discount_amount = 0,
      user_id,
      transaction_id,
      transfer_content,
      qr_content,
      paid_at,
      customer_phone,
      customer_name,
      use_points = false,
      points_to_use = 0,
    } = req.body;

    // DEBUG: Log dữ liệu nhận được
    console.log("[ORDER DEBUG] Received:", {
      voucher_id,
      discount_amount,
      user_id,
      customer_id,
      customer_phone,
      use_points,
      points_to_use,
      employee_id,
      items_count: items?.length,
    });

    if (!Array.isArray(items) || items.length === 0) {
      return res
        .status(400)
        .json({ success: false, message: "Đơn hàng cần có items" });
    }

    await connection.beginTransaction();

    // Kiểm tra voucher nếu được cung cấp
    let finalDiscountAmount = Number(discount_amount) || 0;
    if (voucher_id) {
      const [vouchers] = await connection.execute(
        "SELECT voucher_id, used_count, usage_limit, status, expiry_date FROM vouchers WHERE voucher_id = ? FOR UPDATE",
        [voucher_id],
      );

      if (vouchers.length === 0) {
        throw new Error("Mã voucher không tồn tại");
      }

      const voucher = vouchers[0];

      // Kiểm tra voucher còn hoạt động không
      if (voucher.status !== "active") {
        throw new Error("Mã voucher không còn hoạt động");
      }

      // Kiểm tra hạn sử dụng
      if (voucher.expiry_date && new Date(voucher.expiry_date) < new Date()) {
        throw new Error("Mã voucher đã hết hạn");
      }

      // Kiểm tra giới hạn sử dụng
      if (voucher.usage_limit && voucher.used_count >= voucher.usage_limit) {
        throw new Error("Mã voucher đã hết lượt sử dụng");
      }

      // Cập nhật used_count cho voucher
      await connection.execute(
        "UPDATE vouchers SET used_count = used_count + 1 WHERE voucher_id = ?",
        [voucher_id],
      );

      // Lưu vào bảng user_vouchers nếu user_id có
      if (user_id) {
        await connection.execute(
          `INSERT INTO user_vouchers (user_id, voucher_id, used_count, last_used_at)
           VALUES (?, ?, 1, NOW())
           ON DUPLICATE KEY UPDATE
           used_count = used_count + 1,
           last_used_at = NOW()`,
          [user_id, voucher_id],
        );
      }
    }

    const employeeId = employee_id ? Number(employee_id) : null;
    const hasOrdersShiftId = await ordersHasShiftId(connection);
    const activeShiftId = hasOrdersShiftId
      ? await getActiveShiftId(connection, employeeId)
      : null;
    const columns = await ordersColumns(connection);
    const requestUserId =
      Number(user_id || customer_id || req.get("x-user-id")) || null;
    let customerId = customer_id || (order_type === "online" ? requestUserId : null);
    const normalizedOrderStatus = normalizeOrderStatusValue(
      order_status || status,
      order_type,
    );
    const normalizedPaymentStatus =
      payment_status === "unpaid"
        ? "pending"
        : payment_status || (order_type === "online" ? "pending" : "paid");

    let total = 0;
    const normalizedItems = [];
    for (const item of items) {
      const productId = Number(item.product_id || item.productId);
      const quantity = Number(item.quantity);
      if (!productId || quantity <= 0) {
        throw new Error("Item không hợp lệ");
      }

      const [products] = await connection.execute(
        "SELECT product_id, product_name, price, stock FROM products WHERE product_id = ? FOR UPDATE",
        [productId],
      );
      if (products.length === 0) {
        throw new Error(`Không tìm thấy sản phẩm ${productId}`);
      }
      if (products[0].stock < quantity) {
        throw new Error(`Không đủ tồn kho cho ${products[0].product_name}`);
      }

      const price = Number(item.price ?? products[0].price);
      const subtotal = price * quantity;
      total += subtotal;
      normalizedItems.push({ productId, quantity, price, subtotal });
    }

    const amountAfterVoucher = Math.max(0, total - finalDiscountAmount);
    let pointsUsed = 0;
    let pointsDiscount = 0;
    let loyaltyCustomer = null;
    const loyaltyPhone = loyalty.normalizePhone(customer_phone);
    const wantsLoyalty =
      Boolean(loyaltyPhone) ||
      use_points === true ||
      use_points === "true" ||
      Number(points_to_use || 0) > 0;

    if (wantsLoyalty) {
      loyaltyCustomer = await loyalty.ensureCustomerByPhone(connection, {
        customerName: customer_name || "Khách hàng",
        phone: loyaltyPhone,
      });
      customerId = loyaltyCustomer.user_id;
    }

    if (use_points === true || use_points === "true" || Number(points_to_use || 0) > 0) {
      if (!loyaltyCustomer) {
        throw new Error("Vui lòng tra khách hàng trước khi dùng điểm");
      }
      const redeem = loyalty.validateRedeem({
        pointsToUse: Number(points_to_use || 0),
        availablePoints: Number(loyaltyCustomer.points || 0),
        amountAfterVoucher,
      });
      pointsUsed = redeem.pointsUsed;
      pointsDiscount = redeem.pointsDiscount;
    }

    const finalAmount = Math.max(0, amountAfterVoucher - pointsDiscount);

    const insertColumns = [];
    const insertParams = [];
    const addColumn = (column, value) => {
      insertColumns.push(column);
      insertParams.push(value);
    };

    addColumn("customer_id", customerId || null);
    addColumn("employee_id", employeeId);
    if (hasOrdersShiftId) addColumn("shift_id", activeShiftId);
    addColumn("voucher_id", voucher_id || null);
    addColumn("order_type", order_type);
    addColumn("total_amount", total);
    addColumn("discount_amount", finalDiscountAmount);
    if (columns.has("points_used")) addColumn("points_used", pointsUsed);
    if (columns.has("points_earned")) addColumn("points_earned", 0);
    if (columns.has("points_discount")) addColumn("points_discount", pointsDiscount);
    addColumn("final_amount", finalAmount);
    if (columns.has("payment_method")) addColumn("payment_method", payment_method);
    addColumn("status", normalizedOrderStatus);
    addColumn("payment_status", normalizedPaymentStatus);
    if (columns.has("transaction_id")) addColumn("transaction_id", transaction_id || null);
    if (columns.has("transfer_content")) addColumn("transfer_content", transfer_content || null);
    if (columns.has("paid_at")) {
      addColumn(
        "paid_at",
        normalizedPaymentStatus === "paid" ? (paid_at ? new Date(paid_at) : new Date()) : null,
      );
    }
    if (columns.has("order_status")) addColumn("order_status", normalizedOrderStatus);
    addColumn("shipping_address", shipping_address || null);
    addColumn("note", note || null);
    const insertValues = insertColumns.map(() => "?").join(", ");

    const [orderResult] = await connection.execute(
      `INSERT INTO orders (${insertColumns}) VALUES (${insertValues})`,
      insertParams,
    );

    const generatedTransferContent =
      payment_method === "bank_transfer"
        ? transfer_content || `DH${orderResult.insertId}`
        : transfer_content || null;
    if (generatedTransferContent && columns.has("transfer_content")) {
      await connection.execute(
        "UPDATE orders SET transfer_content = ? WHERE order_id = ?",
        [generatedTransferContent, orderResult.insertId],
      );
    }

    for (const item of normalizedItems) {
      await connection.execute(
        `INSERT INTO order_items (order_id, product_id, quantity, price, subtotal)
         VALUES (?, ?, ?, ?, ?)`,
        [
          orderResult.insertId,
          item.productId,
          item.quantity,
          item.price,
          item.subtotal,
        ],
      );
      await connection.execute(
        "UPDATE products SET stock = stock - ? WHERE product_id = ?",
        [item.quantity, item.productId],
      );
    }

    const paymentColumns = await paymentsColumns(connection);
    const paymentInsertColumns = ["order_id", "method", "amount", "status"];
    const paymentParams = [
      orderResult.insertId,
      payment_method,
      finalAmount,
      normalizedPaymentStatus,
    ];
    if (paymentColumns.has("transaction_id")) {
      paymentInsertColumns.push("transaction_id");
      paymentParams.push(transaction_id || null);
    }
    if (paymentColumns.has("qr_content")) {
      paymentInsertColumns.push("qr_content");
      paymentParams.push(qr_content || generatedTransferContent || null);
    }
    paymentInsertColumns.push("paid_at");
    paymentParams.push(normalizedPaymentStatus === "paid" ? new Date() : null);
    await connection.execute(
      `INSERT INTO payments (${paymentInsertColumns.join(", ")})
       VALUES (${paymentInsertColumns.map(() => "?").join(", ")})`,
      paymentParams,
    );

    if (["paid", "success"].includes(String(normalizedPaymentStatus || "").toLowerCase())) {
      await loyalty.finalizePaidOrderLoyalty(connection, orderResult.insertId);
    }

    await connection.commit();
    const order = await fetchOrder(orderResult.insertId);
    res
      .status(201)
      .json({ success: true, message: "Đã tạo đơn hàng", data: order });
  } catch (error) {
    await connection.rollback();
    const isBusinessError =
      error.message &&
      (error.message.startsWith("Không đủ tồn kho") ||
        error.message.includes("không hợp lệ") ||
        error.message.includes("không tìm thấy") ||
        error.message.includes("không tồn tại") ||
        error.message.includes("không còn hoạt động") ||
        error.message.includes("đã hết hạn") ||
        error.message.includes("đã hết lượt") ||
        error.message.includes("Vui lòng"));
    res
      .status(isBusinessError ? 400 : 500)
      .json({
        success: false,
        message: isBusinessError ? error.message : "Lỗi tạo đơn hàng",
        error: error.message,
      });
  } finally {
    connection.release();
  }
});

module.exports = router;
