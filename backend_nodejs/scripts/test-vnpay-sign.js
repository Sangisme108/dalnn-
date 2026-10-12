/**
 * Quick check: VNPay sign + verify round-trip (no network).
 * Run: node scripts/test-vnpay-sign.js
 */
require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });

process.env.VNP_TMN_CODE = process.env.VNP_TMN_CODE || "DEMO";
process.env.VNP_HASH_SECRET = process.env.VNP_HASH_SECRET || "SECRETKEY";
process.env.VNP_URL =
  process.env.VNP_URL || "https://sandbox.vnpayment.vn/paymentv2/vpcpay.html";
process.env.VNP_RETURN_URL =
  process.env.VNP_RETURN_URL || "https://example.com/api/payments/vnpay-return";
process.env.VNP_IPN_URL =
  process.env.VNP_IPN_URL || "https://example.com/api/payments/vnpay-ipn";

const vnpay = require("../src/services/vnpay.service");

const { paymentUrl, txnRef, vnpAmount } = vnpay.createPaymentUrl({
  orderId: 99,
  amount: 150000,
  orderInfo: "Test order 99",
  ipAddr: "127.0.0.1",
  txnRef: vnpay.buildTxnRef(99),
});

const query = Object.fromEntries(new URL(paymentUrl).searchParams.entries());
const verified = vnpay.verifyIpnQuery(query);

console.log("txnRef:", txnRef);
console.log("vnpAmount:", vnpAmount);
console.log("signature valid:", verified.isValid);
console.log("parsed orderId:", vnpay.parseOrderIdFromTxnRef(txnRef));

if (!verified.isValid) {
  process.exitCode = 1;
}
