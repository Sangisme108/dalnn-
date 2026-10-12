const { hashPassword } = require("./auth.service");

const POINTS_STEP = 100;
const DISCOUNT_PER_STEP = 10000;

function normalizePhone(phone) {
  return String(phone || "").replace(/\D/g, "");
}

function calculateTierMultiplier(currentPoints) {
  if (currentPoints >= 1000) return 1.5;
  if (currentPoints >= 500) return 1.2;
  return 1;
}

function calculateEarnPoints(amount, currentPoints) {
  const basePoints = Math.floor(Number(amount || 0) / 10000);
  return Math.max(0, Math.floor(basePoints * calculateTierMultiplier(currentPoints)));
}

function pointsToDiscount(points) {
  return Math.floor(Number(points || 0) / POINTS_STEP) * DISCOUNT_PER_STEP;
}

function redeemQuote(points, amountAfterVoucher = null) {
  const safePoints = Math.max(0, Number(points || 0));
  const byBalance = Math.floor(safePoints / POINTS_STEP) * POINTS_STEP;
  let maxRedeemPoints = byBalance;

  if (amountAfterVoucher != null) {
    const maxDiscountByAmount = Math.max(0, Number(amountAfterVoucher || 0));
    const byAmount = Math.floor(maxDiscountByAmount / DISCOUNT_PER_STEP) * POINTS_STEP;
    maxRedeemPoints = Math.min(maxRedeemPoints, byAmount);
  }

  return {
    canRedeem: maxRedeemPoints >= POINTS_STEP,
    maxRedeemPoints,
    maxDiscount: pointsToDiscount(maxRedeemPoints),
  };
}

async function getCustomerRoleId(connection) {
  const [roles] = await connection.execute(
    "SELECT role_id FROM roles WHERE role_name = 'customer' LIMIT 1",
  );
  if (roles.length === 0) {
    throw new Error("Chưa có role 'customer' trong database");
  }
  return roles[0].role_id;
}

async function findCustomerByPhone(connection, phone, { forUpdate = false } = {}) {
  const normalizedPhone = normalizePhone(phone);
  if (!normalizedPhone) return null;
  const [rows] = await connection.execute(
    `SELECT u.user_id, u.full_name, u.phone, u.points, r.role_name
     FROM users u
     JOIN roles r ON r.role_id = u.role_id
     WHERE u.phone = ?
     LIMIT 1 ${forUpdate ? "FOR UPDATE" : ""}`,
    [normalizedPhone],
  );
  return rows[0] || null;
}

async function ensureCustomerByPhone(connection, { customerName, phone }) {
  const normalizedPhone = normalizePhone(phone);
  const name = String(customerName || "").trim();
  if (!name) throw new Error("Vui lòng nhập tên khách hàng");
  if (normalizedPhone.length < 8 || normalizedPhone.length > 15) {
    throw new Error("Số điện thoại không hợp lệ");
  }

  const existing = await findCustomerByPhone(connection, normalizedPhone, { forUpdate: true });
  if (existing) {
    if (existing.role_name !== "customer") {
      const err = new Error("Số điện thoại này đang thuộc tài khoản không phải khách hàng");
      err.status = 409;
      throw err;
    }
    if (name && existing.full_name !== name) {
      await connection.execute("UPDATE users SET full_name = ? WHERE user_id = ?", [
        name,
        existing.user_id,
      ]);
      existing.full_name = name;
    }
    return existing;
  }

  const customerRoleId = await getCustomerRoleId(connection);
  const syntheticEmail = `offline_${normalizedPhone}@smartpos.local`;
  const membershipCode = `MB${Date.now()}${normalizedPhone.slice(-4)}`;
  const offlinePasswordHash = await hashPassword(`offline_${normalizedPhone}_${Date.now()}`);
  const [result] = await connection.execute(
    `INSERT INTO users
      (full_name, email, phone, password, role_id, points, membership_code, status)
     VALUES (?, ?, ?, ?, ?, 0, ?, 'active')`,
    [name, syntheticEmail, normalizedPhone, offlinePasswordHash, customerRoleId, membershipCode],
  );

  return {
    user_id: result.insertId,
    full_name: name,
    phone: normalizedPhone,
    points: 0,
    role_name: "customer",
  };
}

function validateRedeem({ pointsToUse, availablePoints, amountAfterVoucher }) {
  const points = Number(pointsToUse || 0);
  if (points <= 0) return { pointsUsed: 0, pointsDiscount: 0 };
  if (points % POINTS_STEP !== 0) {
    throw new Error("Số điểm sử dụng phải là bội số của 100");
  }
  if (points > Number(availablePoints || 0)) {
    throw new Error("Số điểm sử dụng lớn hơn điểm hiện có");
  }
  const quote = redeemQuote(availablePoints, amountAfterVoucher);
  if (points > quote.maxRedeemPoints) {
    throw new Error("Số điểm sử dụng vượt quá số tiền cần thanh toán");
  }
  return { pointsUsed: points, pointsDiscount: pointsToDiscount(points) };
}

async function transactionExists(connection, orderId, type) {
  if (!orderId) return false;
  const [rows] = await connection.execute(
    "SELECT loyalty_id FROM loyalty_transactions WHERE order_id = ? AND type = ? LIMIT 1",
    [orderId, type],
  );
  return rows.length > 0;
}

async function updateOrderLoyaltyColumns(connection, orderId, values) {
  const [cols] = await connection.execute(
    `SELECT COLUMN_NAME
     FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = 'orders'
       AND COLUMN_NAME IN ('points_used', 'points_earned', 'points_discount')`,
  );
  const available = new Set(cols.map((row) => row.COLUMN_NAME));
  const setParts = [];
  const params = [];
  for (const [column, value] of Object.entries(values)) {
    if (!available.has(column)) continue;
    setParts.push(`${column} = ?`);
    params.push(value);
  }
  if (setParts.length === 0) return;
  params.push(orderId);
  await connection.execute(
    `UPDATE orders SET ${setParts.join(", ")} WHERE order_id = ?`,
    params,
  );
}

async function finalizePaidOrderLoyalty(connection, orderId) {
  const [orders] = await connection.execute(
    `SELECT *
     FROM orders
     WHERE order_id = ?
     LIMIT 1
     FOR UPDATE`,
    [orderId],
  );
  const order = orders[0];
  if (!order) return null;
  if (!["paid", "success"].includes(String(order.payment_status || "").toLowerCase())) {
    return null;
  }
  if (!order.customer_id) return null;

  const pointsUsed = Number(order.points_used || 0);
  const finalAmount = Number(order.final_amount || 0);
  let pointsDiscount = Number(order.points_discount || 0);
  let pointsEarned = Number(order.points_earned || 0);
  let customer;

  if (pointsUsed > 0 && !(await transactionExists(connection, orderId, "redeem"))) {
    const [customers] = await connection.execute(
      "SELECT user_id, full_name, phone, points FROM users WHERE user_id = ? FOR UPDATE",
      [order.customer_id],
    );
    customer = customers[0];
    if (!customer) throw new Error("Không tìm thấy khách hàng để trừ điểm");
    const validated = validateRedeem({
      pointsToUse: pointsUsed,
      availablePoints: Number(customer.points || 0),
      amountAfterVoucher: Number(order.final_amount || 0) + pointsDiscount,
    });
    pointsDiscount = validated.pointsDiscount;
    await connection.execute("UPDATE users SET points = points - ? WHERE user_id = ?", [
      validated.pointsUsed,
      customer.user_id,
    ]);
    await connection.execute(
      `INSERT INTO loyalty_transactions (user_id, order_id, points_change, type, note)
       VALUES (?, ?, ?, 'redeem', ?)`,
      [
        customer.user_id,
        orderId,
        -validated.pointsUsed,
        `Dùng ${validated.pointsUsed} điểm giảm ${validated.pointsDiscount.toLocaleString("vi-VN")} VND`,
      ],
    );
    customer.points = Number(customer.points || 0) - validated.pointsUsed;
  }

  if (!(await transactionExists(connection, orderId, "earn"))) {
    if (!customer) {
      const [customers] = await connection.execute(
        "SELECT user_id, full_name, phone, points FROM users WHERE user_id = ? FOR UPDATE",
        [order.customer_id],
      );
      customer = customers[0];
    }
    if (!customer) throw new Error("Không tìm thấy khách hàng để cộng điểm");
    pointsEarned = calculateEarnPoints(finalAmount, Number(customer.points || 0));
    if (pointsEarned > 0) {
      await connection.execute("UPDATE users SET points = points + ? WHERE user_id = ?", [
        pointsEarned,
        customer.user_id,
      ]);
    }
    await connection.execute(
      `INSERT INTO loyalty_transactions (user_id, order_id, points_change, type, note)
       VALUES (?, ?, ?, 'earn', ?)`,
      [
        customer.user_id,
        orderId,
        pointsEarned,
        `Tích điểm theo đơn ${Number(finalAmount || 0).toLocaleString("vi-VN")} VND`,
      ],
    );
    customer.points = Number(customer.points || 0) + pointsEarned;
  }

  await updateOrderLoyaltyColumns(connection, orderId, {
    points_used: pointsUsed,
    points_discount: pointsDiscount,
    points_earned: pointsEarned,
  });

  return {
    customerId: order.customer_id,
    pointsUsed,
    pointsDiscount,
    pointsEarned,
    totalPoints: customer ? Number(customer.points || 0) : null,
  };
}

module.exports = {
  POINTS_STEP,
  DISCOUNT_PER_STEP,
  normalizePhone,
  calculateTierMultiplier,
  calculateEarnPoints,
  pointsToDiscount,
  redeemQuote,
  findCustomerByPhone,
  ensureCustomerByPhone,
  validateRedeem,
  finalizePaidOrderLoyalty,
  updateOrderLoyaltyColumns,
  transactionExists,
};
