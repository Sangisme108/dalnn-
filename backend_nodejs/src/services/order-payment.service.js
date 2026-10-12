const pool = require("../config/db");
const loyalty = require("./loyalty.service");

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

async function insertPaymentRecord(
  connection,
  { orderId, method, amount, status, transactionId, paidAt },
) {
  const columns = await paymentsColumns(connection);
  const insertColumns = ["order_id", "method", "amount", "status"];
  const params = [orderId, method, amount, status];
  if (columns.has("transaction_id")) {
    insertColumns.push("transaction_id");
    params.push(transactionId || null);
  }
  insertColumns.push("paid_at");
  params.push(paidAt);
  await connection.execute(
    `INSERT INTO payments (${insertColumns.join(", ")})
     VALUES (${insertColumns.map(() => "?").join(", ")})`,
    params,
  );
}

async function getOrderForPayment(orderId, connection = pool) {
  const columns = await ordersColumns(connection);
  const orderTypeSelect = columns.has("order_type")
    ? "order_type"
    : "NULL AS order_type";
  const deliveryMethodSelect = columns.has("delivery_method")
    ? "delivery_method"
    : "NULL AS delivery_method";
  const paymentMethodSelect = columns.has("payment_method")
    ? "payment_method"
    : "NULL AS payment_method";
  const orderStatusSelect = columns.has("order_status")
    ? "order_status"
    : "NULL AS order_status";
  const transactionSelect = columns.has("transaction_id")
    ? "transaction_id"
    : "NULL AS transaction_id";
  const transferContentSelect = columns.has("transfer_content")
    ? "transfer_content"
    : "NULL AS transfer_content";
  const paidAtSelect = columns.has("paid_at") ? "paid_at" : "NULL AS paid_at";
  const pointsUsedSelect = columns.has("points_used") ? "points_used" : "0 AS points_used";
  const pointsEarnedSelect = columns.has("points_earned") ? "points_earned" : "0 AS points_earned";
  const pointsDiscountSelect = columns.has("points_discount")
    ? "points_discount"
    : "0 AS points_discount";
  const [rows] = await connection.execute(
    `SELECT order_id, customer_id, employee_id, ${orderTypeSelect}, ${deliveryMethodSelect},
            total_amount, discount_amount, final_amount,
            ${paymentMethodSelect}, payment_status, status, ${orderStatusSelect},
            ${transactionSelect}, ${transferContentSelect}, ${paidAtSelect},
            ${pointsUsedSelect}, ${pointsEarnedSelect}, ${pointsDiscountSelect},
            created_at
     FROM orders
     WHERE order_id = ?
     LIMIT 1`,
    [orderId],
  );
  return rows[0] || null;
}

async function markOrderPaid(connection, orderId, { transactionId, gateway = "vnpay" }) {
  const order = await getOrderForPayment(orderId, connection);
  if (!order) {
    return { ok: false, code: "ORDER_NOT_FOUND", message: "Không tìm thấy đơn hàng" };
  }

  if (["paid", "success"].includes(String(order.payment_status || "").toLowerCase())) {
    return { ok: true, alreadyPaid: true, order };
  }

  const columns = await ordersColumns(connection);
  const isOffline = String(order.order_type || "").toLowerCase() === "offline";
  const nextOrderStatus = isOffline ? "completed" : order.order_status || order.status || "pending";
  const nextStatus = isOffline ? "completed" : order.status || "pending";

  const setParts = ["payment_status = 'paid'"];
  const params = [];

  if (columns.has("payment_method")) {
    setParts.push("payment_method = ?");
    params.push(gateway);
  }
  if (columns.has("order_status")) {
    setParts.push("order_status = ?");
    params.push(nextOrderStatus);
  }
  setParts.push("status = ?");
  params.push(nextStatus);

  if (columns.has("transaction_id")) {
    setParts.push("transaction_id = ?");
    params.push(transactionId);
  }
  if (columns.has("paid_at")) {
    setParts.push("paid_at = NOW()");
  }
  if (columns.has("updated_at")) {
    setParts.push("updated_at = NOW()");
  }

  params.push(orderId);
  await connection.execute(
    `UPDATE orders SET ${setParts.join(", ")} WHERE order_id = ?`,
    params,
  );

  await insertPaymentRecord(connection, {
    orderId,
    method: gateway,
    amount: Number(order.final_amount),
    status: "paid",
    transactionId,
    paidAt: new Date(),
  });

  await loyalty.finalizePaidOrderLoyalty(connection, orderId);

  return { ok: true, alreadyPaid: false, order };
}

async function findPendingOrderByTransferContent(connection, transferContent) {
  const columns = await ordersColumns(connection);
  const normalizedCode = String(transferContent || "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
  const orderIdFromCode = Number(normalizedCode.replace(/^DH/, "")) || 0;
  const whereTransfer = columns.has("transfer_content")
    ? "(UPPER(transfer_content) = ? OR note LIKE ? OR order_id = ?)"
    : "(note LIKE ? OR order_id = ?)";
  const params = columns.has("transfer_content")
    ? [normalizedCode, `%${normalizedCode}%`, orderIdFromCode]
    : [`%${normalizedCode}%`, orderIdFromCode];
  const [rows] = await connection.execute(
    `SELECT order_id
     FROM orders
     WHERE ${whereTransfer}
       AND LOWER(COALESCE(payment_status, 'pending')) NOT IN ('paid', 'success')
     ORDER BY created_at DESC, order_id DESC
     LIMIT 1`,
    params,
  );
  return rows[0]?.order_id || null;
}

async function markOrderFailed(connection, orderId, { transactionId, gateway = "vnpay" }) {
  const order = await getOrderForPayment(orderId, connection);
  if (!order) {
    return { ok: false, code: "ORDER_NOT_FOUND", message: "Không tìm thấy đơn hàng" };
  }

  if (["paid", "success"].includes(String(order.payment_status || "").toLowerCase())) {
    return { ok: true, alreadyPaid: true, order };
  }

  const columns = await ordersColumns(connection);
  const setParts = ["payment_status = 'failed'"];
  const params = [];

  if (columns.has("transaction_id") && transactionId) {
    setParts.push("transaction_id = ?");
    params.push(transactionId);
  }
  if (columns.has("updated_at")) {
    setParts.push("updated_at = NOW()");
  }

  params.push(orderId);
  await connection.execute(
    `UPDATE orders SET ${setParts.join(", ")} WHERE order_id = ?`,
    params,
  );

  await insertPaymentRecord(connection, {
    orderId,
    method: gateway,
    amount: Number(order.final_amount),
    status: "failed",
    transactionId,
    paidAt: null,
  });

  return { ok: true, order };
}

module.exports = {
  ordersColumns,
  paymentsColumns,
  getOrderForPayment,
  findPendingOrderByTransferContent,
  markOrderPaid,
  markOrderFailed,
};
