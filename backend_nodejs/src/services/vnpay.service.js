const crypto = require("crypto");

const VNP_VERSION = "2.1.0";
const VNP_COMMAND = "pay";
const VNP_CURR_CODE = "VND";
const VNP_LOCALE = "vn";
const VNP_ORDER_TYPE = "other";

function requireEnv(name) {
  const value = process.env[name];
  if (!value || !String(value).trim()) {
    throw new Error(`Thiếu cấu hình môi trường ${name}`);
  }
  return String(value).trim();
}

function envOrDevFallback(name, fallback) {
  const value = process.env[name];
  if (value && String(value).trim()) {
    return String(value).trim();
  }

  if (process.env.NODE_ENV === "production") {
    return requireEnv(name);
  }

  console.warn(`[VNPay] ${name} chưa có trong .env, dùng cấu hình sandbox demo cho môi trường dev.`);
  return fallback;
}

function sortAndEncodeParams(params) {
  const entries = Object.keys(params)
    .filter((key) => params[key] !== undefined && params[key] !== null && params[key] !== "")
    .sort()
    .map((key) => `${encodeURIComponent(key)}=${encodeURIComponent(String(params[key]))}`);
  return entries.join("&");
}

function hmacSha512(secret, data) {
  return crypto.createHmac("sha512", secret).update(Buffer.from(data, "utf-8")).digest("hex");
}

function formatVnpDate(date = new Date()) {
  const pad = (n) => String(n).padStart(2, "0");
  return (
    date.getFullYear().toString() +
    pad(date.getMonth() + 1) +
    pad(date.getDate()) +
    pad(date.getHours()) +
    pad(date.getMinutes()) +
    pad(date.getSeconds())
  );
}

function getConfig() {
  const localBackendUrl = `http://localhost:${process.env.PORT || 3000}`;
  return {
    tmnCode: envOrDevFallback("VNP_TMN_CODE", "2QXUI4J4"),
    hashSecret: envOrDevFallback("VNP_HASH_SECRET", "1H4TV13VE5Y61RJ8Y1L86I6Q2Q8ZV8V4"),
    paymentUrl: envOrDevFallback("VNP_URL", "https://sandbox.vnpayment.vn/paymentv2/vpcpay.html"),
    returnUrl: envOrDevFallback("VNP_RETURN_URL", `${localBackendUrl}/api/payments/vnpay-return`),
    ipnUrl: envOrDevFallback("VNP_IPN_URL", `${localBackendUrl}/api/payments/vnpay-ipn`),
  };
}

function buildTxnRef(orderId) {
  return `${orderId}_${Date.now().toString().slice(-10)}`;
}

function parseOrderIdFromTxnRef(txnRef) {
  if (!txnRef) return null;
  const value = String(txnRef);
  const underscore = value.indexOf("_");
  if (underscore > 0) {
    const orderId = Number(value.slice(0, underscore));
    return Number.isFinite(orderId) && orderId > 0 ? orderId : null;
  }
  const match = value.match(/^(\d+)/);
  const orderId = match ? Number(match[1]) : null;
  return Number.isFinite(orderId) && orderId > 0 ? orderId : null;
}

function createPaymentUrl({
  orderId,
  amount,
  orderInfo,
  ipAddr,
  txnRef,
  bankCode,
  expireMinutes = 15,
}) {
  const config = getConfig();
  const createDate = new Date();
  const expireDate = new Date(createDate.getTime() + expireMinutes * 60 * 1000);
  const vnpAmount = Math.round(Number(amount) * 100);

  const params = {
    vnp_Version: VNP_VERSION,
    vnp_Command: VNP_COMMAND,
    vnp_TmnCode: config.tmnCode,
    vnp_Amount: vnpAmount,
    vnp_CurrCode: VNP_CURR_CODE,
    vnp_TxnRef: txnRef,
    vnp_OrderInfo: orderInfo,
    vnp_OrderType: VNP_ORDER_TYPE,
    vnp_Locale: VNP_LOCALE,
    vnp_ReturnUrl: config.returnUrl,
    vnp_IpAddr: ipAddr || "127.0.0.1",
    vnp_CreateDate: formatVnpDate(createDate),
    vnp_ExpireDate: formatVnpDate(expireDate),
  };

  if (bankCode) {
    params.vnp_BankCode = String(bankCode).trim();
  }

  const signData = sortAndEncodeParams(params);
  const secureHash = hmacSha512(config.hashSecret, signData);
  const paymentUrl = `${config.paymentUrl}?${signData}&vnp_SecureHash=${secureHash}`;

  return { paymentUrl, txnRef, vnpAmount, params };
}

function verifyIpnQuery(query) {
  const config = getConfig();
  const input = { ...query };
  const receivedHash = input.vnp_SecureHash;
  delete input.vnp_SecureHash;
  delete input.vnp_SecureHashType;

  const signData = sortAndEncodeParams(input);
  const expectedHash = hmacSha512(config.hashSecret, signData);
  const isValid = Boolean(receivedHash) && receivedHash === expectedHash;

  return {
    isValid,
    txnRef: input.vnp_TxnRef,
    responseCode: input.vnp_ResponseCode,
    transactionNo: input.vnp_TransactionNo,
    amount: Number(input.vnp_Amount || 0),
    bankCode: input.vnp_BankCode,
    payDate: input.vnp_PayDate,
    orderInfo: input.vnp_OrderInfo,
    raw: input,
  };
}

module.exports = {
  buildTxnRef,
  parseOrderIdFromTxnRef,
  createPaymentUrl,
  verifyIpnQuery,
  getConfig,
};
