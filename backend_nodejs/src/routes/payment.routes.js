const express = require("express");
const pool = require("../config/db");
const { requireAuth } = require("../middlewares/auth.middleware");
const vnpay = require("../services/vnpay.service");
const orderPayment = require("../services/order-payment.service");

const router = express.Router();
const BANK_TRANSFER_ACCOUNT_NUMBER =
  process.env.BANK_TRANSFER_ACCOUNT_NUMBER || "0363489746";

function digitsOnly(value) {
  return String(value || "").replace(/\D/g, "");
}

function currentUserId(req) {
  return Number(req.user?.id || req.user?.user_id || req.get("x-user-id"));
}

function clientIp(req) {
  const forwarded = req.headers["x-forwarded-for"];
  if (forwarded) {
    return String(forwarded).split(",")[0].trim();
  }
  return req.ip || req.socket?.remoteAddress || "127.0.0.1";
}

function normalizeBankWebhookPayload(payload) {
  const data = payload?.data || payload?.transaction || payload;
  const rawAmount =
    data.amount ??
      data.transferAmount ??
    data.transactionAmount ??
    data.creditAmount ??
      data.money ??
      0;
  const amount = typeof rawAmount === "number"
    ? rawAmount
    : Number(String(rawAmount).replace(/[.,]0$/, "").replace(/\D/g, ""));
  const description = String(
    data.description ??
      data.content ??
      data.addInfo ??
      data.memo ??
      data.remark ??
      data.transactionContent ??
      data.transaction_content ??
      "",
  );
  const orderCode =
    extractTransferContent(data.code) ||
    extractTransferContent(description);
  const bankReference = String(description || "")
    .toUpperCase()
    .match(/\bFT[0-9A-Z]+\b/)?.[0];
  const transactionId = String(
    data.transactionId ??
      data.transaction_id ??
      data.refId ??
      data.ref_id ??
      data.reference ??
      data.referenceId ??
      data.referenceCode ??
      data.reference_code ??
      data.tid ??
      bankReference ??
      data.id ??
      data.code ??
      "",
  );
  const accountNumber = digitsOnly(
    data.accountNumber ??
      data.bankAccount ??
      data.bankSubAccId ??
      data.bank_sub_acc_id ??
      data.accountNo ??
      data.creditAccount ??
      data.virtualAccountNumber ??
      data.virtual_account_number ??
      data.subAccount ??
      data.sub_account ??
      "",
  );
  const transactionDate =
    data.transactionDate ??
    data.transaction_date ??
    data.when ??
    data.createdAt ??
    data.time ??
    null;
  const provider = String(payload.provider || data.provider || "bank_webhook");
  const transferType = String(
    data.transferType ?? data.transfer_type ?? data.type ?? "",
  ).toLowerCase();

  return {
    amount,
    description,
    orderCode,
    transactionId,
    accountNumber,
    transactionDate,
    provider,
    transferType,
  };
}

function normalizeBankWebhookPayloads(payload) {
  const data = payload?.data || payload?.transaction || payload?.transactions;
  if (Array.isArray(data)) {
    return data.map((item) =>
      normalizeBankWebhookPayload({
        provider: payload.provider,
        data: item,
      }),
    );
  }
  return [normalizeBankWebhookPayload(payload)];
}

function verifyBankWebhook(req) {
  const expected = process.env.BANK_WEBHOOK_SECRET;
  if (!expected) return true;
  const provided =
    req.get("x-bank-webhook-secret") ||
    req.get("x-webhook-secret") ||
    req.query.secret ||
    req.body?.secret;
  return provided === expected;
}

function extractTransferContent(description) {
  const match = String(description || "")
    .toUpperCase()
    .replace(/\s+/g, "")
    .match(/DH[0-9A-Z]+/);
  return match ? match[0] : null;
}

async function handleNormalizedBankTransaction(connection, normalized, rawPayload) {
  if (normalized.transferType && !["in", "credit", "deposit"].includes(normalized.transferType)) {
    return {
      success: true,
      message: "Bỏ qua giao dịch không phải tiền vào",
      skipped: true,
    };
  }

  const transferContent =
    normalized.orderCode || extractTransferContent(normalized.description);
  if (!normalized.transactionId) {
    return { success: false, status: 400, message: "Thiếu transactionId" };
  }
  if (!transferContent) {
    return {
      success: true,
      message: "Không tìm thấy mã đơn trong nội dung",
      skipped: true,
    };
  }
  if (
    normalized.accountNumber &&
    normalized.accountNumber !== digitsOnly(BANK_TRANSFER_ACCOUNT_NUMBER)
  ) {
    return {
      success: true,
      message: "Không phải tài khoản nhận của hệ thống",
      skipped: true,
    };
  }

  const [duplicate] = await connection.execute(
    "SELECT id, order_id FROM payment_transactions WHERE transaction_id = ? LIMIT 1",
    [normalized.transactionId],
  );
  if (duplicate.length > 0) {
    return {
      success: true,
      message: "Giao dịch đã được xử lý trước đó",
      data: { orderId: duplicate[0].order_id, duplicate: true },
    };
  }

  const orderId = await orderPayment.findPendingOrderByTransferContent(
    connection,
    transferContent,
  );
  if (!orderId) {
    await connection.execute(
      `INSERT INTO payment_transactions
        (order_id, transaction_id, amount, description, provider, account_number, raw_payload)
       VALUES (NULL, ?, ?, ?, ?, ?, ?)`,
      [
        normalized.transactionId,
        normalized.amount,
        normalized.description,
        normalized.provider,
        normalized.accountNumber || null,
        JSON.stringify(rawPayload),
      ],
    );
    return {
      success: true,
      message: "Không tìm thấy order pending phù hợp",
      skipped: true,
      data: { transferContent },
    };
  }

  const order = await orderPayment.getOrderForPayment(orderId, connection);
  const expectedAmount = Number(order.final_amount || 0);
  if (normalized.amount < expectedAmount) {
    return {
      success: false,
      status: 400,
      message: "Số tiền nhận nhỏ hơn tổng đơn hàng",
      data: { orderId, amount: normalized.amount, expectedAmount },
    };
  }

  await connection.execute(
    `INSERT INTO payment_transactions
      (order_id, transaction_id, amount, description, provider, account_number, raw_payload)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [
      orderId,
      normalized.transactionId,
      normalized.amount,
      normalized.description,
      normalized.provider,
      normalized.accountNumber || null,
      JSON.stringify(rawPayload),
    ],
  );

  await orderPayment.markOrderPaid(connection, orderId, {
    transactionId: normalized.transactionId,
    gateway: "bank_transfer",
  });

  return {
    success: true,
    message: "Đã xác nhận thanh toán chuyển khoản",
    data: { orderId, paymentStatus: "paid", transferContent },
  };
}

async function canAccessOrder(userId, order) {
  if (!userId || !order) return false;
  if (Number(order.customer_id || 0) === userId) return true;
  if (Number(order.employee_id || 0) === userId) return true;

  const [users] = await pool.execute(
    `SELECT r.role_name
     FROM users u
     LEFT JOIN roles r ON r.role_id = u.role_id
     WHERE u.user_id = ?
     LIMIT 1`,
    [userId],
  );
  const role = String(users[0]?.role_name || "").toLowerCase();
  return role.includes("admin") || role.includes("quản");
}

async function processVnpayCallback(query) {
  const verified = vnpay.verifyIpnQuery(query);
  if (!verified.isValid) {
    return {
      httpStatus: 400,
      rspCode: "97",
      message: "Invalid signature",
      paymentStatus: "failed",
      orderId: vnpay.parseOrderIdFromTxnRef(verified.txnRef),
    };
  }

  const orderId = vnpay.parseOrderIdFromTxnRef(verified.txnRef);
  if (!orderId) {
    return {
      httpStatus: 400,
      rspCode: "01",
      message: "Order not found",
      paymentStatus: "failed",
      orderId: null,
    };
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const order = await orderPayment.getOrderForPayment(orderId, connection);
    if (!order) {
      await connection.rollback();
      return {
        httpStatus: 404,
        rspCode: "01",
        message: "Order not found",
        paymentStatus: "failed",
        orderId,
      };
    }

    const expectedAmount = Math.round(Number(order.final_amount) * 100);
    if (expectedAmount !== verified.amount) {
      await connection.rollback();
      return {
        httpStatus: 400,
        rspCode: "04",
        message: "Invalid amount",
        paymentStatus: "failed",
        orderId,
      };
    }

    if (verified.responseCode === "00") {
      const result = await orderPayment.markOrderPaid(connection, orderId, {
        transactionId: verified.transactionNo || verified.txnRef,
        gateway: "vnpay",
      });
      await connection.commit();
      return {
        httpStatus: 200,
        rspCode: "00",
        message: "Confirm Success",
        paymentStatus: "paid",
        orderId,
        alreadyPaid: result.alreadyPaid,
      };
    }

    await orderPayment.markOrderFailed(connection, orderId, {
      transactionId: verified.transactionNo || verified.txnRef,
      gateway: "vnpay",
    });
    await connection.commit();
    return {
      httpStatus: 200,
      rspCode: "00",
      message: "Confirm Success",
      paymentStatus: "failed",
      orderId,
    };
  } catch (error) {
    await connection.rollback();
    return {
      httpStatus: 500,
      rspCode: "99",
      message: error.message,
      paymentStatus: "failed",
      orderId,
    };
  } finally {
    connection.release();
  }
}

function renderReturnHtml({ title, message, paymentStatus, orderId }) {
  const statusColor =
    paymentStatus === "paid" ? "#1B7F4D" : paymentStatus === "pending" ? "#B45309" : "#B91C1C";
  return `<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${title}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f6f7f9; margin: 0; }
    .card { max-width: 420px; margin: 48px auto; background: #fff; border-radius: 16px; padding: 24px; box-shadow: 0 8px 24px rgba(0,0,0,.08); }
    h1 { font-size: 22px; margin: 0 0 8px; color: ${statusColor}; }
    p { color: #374151; line-height: 1.5; }
    .meta { margin-top: 16px; font-size: 14px; color: #6b7280; }
  </style>
</head>
<body>
  <div class="card">
    <h1>${title}</h1>
    <p>${message}</p>
    <div class="meta">Mã đơn: #${orderId || "-"}<br/>Trạng thái: ${paymentStatus}</div>
    <p class="meta">Bạn có thể quay lại ứng dụng. Ứng dụng sẽ tự kiểm tra trạng thái thanh toán.</p>
  </div>
</body>
</html>`;
}

router.post("/vnpay/create", requireAuth, async (req, res) => {
  try {
    const userId = currentUserId(req);
    const orderId = Number(req.body.order_id || req.body.orderId);
    if (!userId) {
      return res.status(401).json({ success: false, message: "Vui lòng đăng nhập" });
    }
    if (!orderId) {
      return res.status(400).json({ success: false, message: "Thiếu orderId" });
    }

    const order = await orderPayment.getOrderForPayment(orderId);
    if (!order) {
      return res.status(404).json({ success: false, message: "Không tìm thấy đơn hàng" });
    }
    if (Number(order.customer_id) !== userId) {
      return res.status(403).json({ success: false, message: "Không có quyền thanh toán đơn này" });
    }
    if (["paid", "success"].includes(String(order.payment_status || "").toLowerCase())) {
      return res.status(400).json({ success: false, message: "Đơn hàng đã được thanh toán" });
    }

    const txnRef = vnpay.buildTxnRef(orderId);
    const columns = await orderPayment.ordersColumns(pool);
    if (columns.has("transaction_id")) {
      await pool.execute("UPDATE orders SET transaction_id = ? WHERE order_id = ?", [
        txnRef,
        orderId,
      ]);
    }

    const bankCode = String(req.body.bank_code || req.body.bankCode || "").trim();
    const { paymentUrl, vnpAmount } = vnpay.createPaymentUrl({
      orderId,
      amount: Number(order.final_amount),
      orderInfo: `Thanh toan don hang #${orderId}`,
      ipAddr: clientIp(req),
      txnRef,
      bankCode: bankCode || undefined,
    });

    res.json({
      success: true,
      data: {
        orderId,
        paymentUrl,
        txnRef,
        amount: Number(order.final_amount),
        vnpAmount,
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Không tạo được liên kết VNPay",
      error: error.message,
    });
  }
});

router.get("/vnpay-return", async (req, res) => {
  const result = await processVnpayCallback(req.query);
  const title =
    result.paymentStatus === "paid"
      ? "Thanh toán thành công"
      : result.paymentStatus === "pending"
        ? "Đang chờ xác nhận"
        : "Thanh toán thất bại";
  const message =
    result.paymentStatus === "paid"
      ? "VNPay đã xác nhận thanh toán. Vui lòng quay lại ứng dụng."
      : result.paymentStatus === "pending"
        ? "Giao dịch đang được xử lý."
        : "Giao dịch không thành công hoặc đã bị hủy.";

  res
    .status(result.httpStatus === 500 ? 200 : result.httpStatus)
    .send(renderReturnHtml({ title, message, paymentStatus: result.paymentStatus, orderId: result.orderId }));
});

router.get("/vnpay-ipn", async (req, res) => {
  const result = await processVnpayCallback(req.query);
  res.status(200).json({
    RspCode: result.rspCode,
    Message: result.message,
  });
});

async function bankWebhookHandler(req, res) {
  if (!verifyBankWebhook(req)) {
    return res.status(401).json({ success: false, message: "Webhook token không hợp lệ" });
  }

  if (process.env.NODE_ENV !== "production") {
    console.log("[BANK WEBHOOK]", JSON.stringify(req.body));
  }

  const normalizedItems = normalizeBankWebhookPayloads(req.body);
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const results = [];
    for (const normalized of normalizedItems) {
      const result = await handleNormalizedBankTransaction(
        connection,
        normalized,
        req.body,
      );
      results.push(result);
      if (result.success === false) {
        await connection.rollback();
        return res.status(result.status || 400).json(result);
      }
    }

    await connection.commit();
    const paid = results.find((item) => item.data?.paymentStatus === "paid");
    return res.json({
      success: true,
      message: paid
        ? "Đã xác nhận thanh toán chuyển khoản"
        : "Đã nhận webhook nhưng chưa có đơn nào được xác nhận",
      data: paid?.data || { results },
    });
  } catch (error) {
    await connection.rollback();
    if (error.code === "ER_DUP_ENTRY") {
      return res.json({ success: true, message: "Giao dịch đã được xử lý" });
    }
    return res.status(500).json({
      success: false,
      message: "Lỗi xử lý webhook chuyển khoản",
      error: error.message,
    });
  } finally {
    connection.release();
  }
}

router.post("/bank-webhook", bankWebhookHandler);
router.post("/sepay", bankWebhookHandler);

router.post("/bank-transfer/manual-confirm", requireAuth, async (req, res) => {
  const userId = currentUserId(req);
  const orderId = Number(req.body.order_id || req.body.orderId);
  if (!userId) {
    return res.status(401).json({ success: false, message: "Vui lòng đăng nhập" });
  }
  if (!orderId) {
    return res.status(400).json({ success: false, message: "Thiếu orderId" });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    const order = await orderPayment.getOrderForPayment(orderId, connection);
    if (!order) {
      await connection.rollback();
      return res.status(404).json({ success: false, message: "Không tìm thấy đơn hàng" });
    }
    if (!(await canAccessOrder(userId, order))) {
      await connection.rollback();
      return res.status(403).json({ success: false, message: "Không có quyền xác nhận đơn này" });
    }
    if (
      order.payment_method &&
      String(order.payment_method || "").toLowerCase() !== "bank_transfer"
    ) {
      await connection.rollback();
      return res.status(400).json({ success: false, message: "Đơn hàng không phải thanh toán chuyển khoản" });
    }

    const transactionId =
      order.transaction_id || `MANUAL_BANK_${orderId}_${Date.now()}`;
    await orderPayment.markOrderPaid(connection, orderId, {
      transactionId,
      gateway: "bank_transfer",
    });
    await connection.commit();

    const paidOrder = await orderPayment.getOrderForPayment(orderId);
    return res.json({
      success: true,
      message: "Đã xác nhận chuyển khoản thủ công",
      data: paidOrder,
    });
  } catch (error) {
    await connection.rollback();
    return res.status(500).json({
      success: false,
      message: "Lỗi xác nhận chuyển khoản thủ công",
      error: error.message,
    });
  } finally {
    connection.release();
  }
});

module.exports = router;
