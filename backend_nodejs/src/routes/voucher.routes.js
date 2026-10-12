const express = require("express");
const router = express.Router();
const voucherController = require("../controllers/voucher.controller");
const { requireAuth } = require("../middlewares/auth.middleware");

// PUBLIC ROUTES (khách hàng)
// Validate voucher khi thanh toán
router.post("/validate", voucherController.validateVoucher);

// Lấy danh sách vouchers khả dụng
router.get("/available", voucherController.getAvailableVouchers);

// Lấy chi tiết voucher theo code
router.get("/code/:code", voucherController.getVoucherByCode);

// Lấy danh sách vouchers của user
router.get("/user/:userId", requireAuth, voucherController.getUserVouchers);

router.post("/:id/claim", requireAuth, voucherController.claimVoucher);

// ===== ADMIN ROUTES =====

// Tạo voucher mới (Admin only)
router.post(
  "/",
  requireAuth,
  (req, res, next) => {
    if (req.user.role_name !== "admin") {
      return res.status(403).json({
        success: false,
        message: "Chỉ admin mới có quyền tạo voucher",
      });
    }
    next();
  },
  voucherController.createVoucher,
);

// Lấy tất cả vouchers (Admin only)
router.get(
  "/",
  requireAuth,
  (req, res, next) => {
    if (req.user.role_name !== "admin") {
      return res.status(403).json({
        success: false,
        message: "Chỉ admin mới có quyền xem",
      });
    }
    next();
  },
  voucherController.getAllVouchers,
);

// Cập nhật voucher (Admin only)
router.put(
  "/:id",
  requireAuth,
  (req, res, next) => {
    if (req.user.role_name !== "admin") {
      return res.status(403).json({
        success: false,
        message: "Chỉ admin mới có quyền cập nhật",
      });
    }
    next();
  },
  voucherController.updateVoucher,
);

// Xóa voucher (Admin only)
router.delete(
  "/:id",
  requireAuth,
  (req, res, next) => {
    if (req.user.role_name !== "admin") {
      return res.status(403).json({
        success: false,
        message: "Chỉ admin mới có quyền xóa",
      });
    }
    next();
  },
  voucherController.deleteVoucher,
);

// Xem lịch sử sử dụng voucher (Admin only)
router.get(
  "/:id/usage",
  requireAuth,
  (req, res, next) => {
    if (req.user.role_name !== "admin") {
      return res.status(403).json({
        success: false,
        message: "Chỉ admin mới có quyền xem",
      });
    }
    next();
  },
  voucherController.getVoucherUsage,
);

module.exports = router;
