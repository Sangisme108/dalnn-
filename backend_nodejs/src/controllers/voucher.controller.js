const pool = require("../config/db");

// 1. VALIDATE VOUCHER - Kiểm tra và tính giảm giá
exports.validateVoucher = async (req, res) => {
  const { code, orderTotal, userId } = req.body;

  try {
    // Tìm voucher
    const [vouchers] = await pool.execute(
      'SELECT * FROM vouchers WHERE code = ? AND status = "active"',
      [code],
    );

    if (vouchers.length === 0) {
      return res.status(400).json({
        success: false,
        message: "Mã voucher không tồn tại",
      });
    }

    const voucher = vouchers[0];

    // Kiểm tra hạn dùng
    if (voucher.expiry_date && new Date(voucher.expiry_date) < new Date()) {
      return res.status(400).json({
        success: false,
        message: "Voucher đã hết hạn",
      });
    }

    // Kiểm tra giới hạn dùng toàn bộ
    if (voucher.usage_limit && voucher.used_count >= voucher.usage_limit) {
      return res.status(400).json({
        success: false,
        message: "Voucher đã hết lượt dùng",
      });
    }

    // Kiểm tra đơn tối thiểu
    if (orderTotal < voucher.min_order_amount) {
      return res.status(400).json({
        success: false,
        message: `Đơn hàng phải tối thiểu ${voucher.min_order_amount.toLocaleString("vi-VN")} VND`,
      });
    }

    // Tính giảm giá
    let discountAmount = 0;
    if (voucher.discount_type === "fixed") {
      discountAmount = voucher.discount_value;
    } else if (voucher.discount_type === "percent") {
      discountAmount = orderTotal * (voucher.discount_value / 100);
      if (voucher.max_discount && discountAmount > voucher.max_discount) {
        discountAmount = voucher.max_discount;
      }
    }

    // Không được giảm quá toàn bộ tiền
    discountAmount = Math.min(discountAmount, orderTotal);

    res.json({
      success: true,
      voucher: {
        id: voucher.voucher_id,
        code: voucher.code,
        description: voucher.description,
        discountAmount: parseFloat(discountAmount.toFixed(2)),
        finalTotal: parseFloat((orderTotal - discountAmount).toFixed(2)),
      },
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 2. GET ALL VOUCHERS - Lấy danh sách vouchers khả dụng (cho user)
exports.getAvailableVouchers = async (req, res) => {
  try {
    const [vouchers] = await pool.execute(
      `SELECT voucher_id, code, description, discount_type, discount_value,
              min_order_amount, max_discount, usage_limit, used_count,
              expiry_date, status, created_at
       FROM vouchers
       WHERE status = 'active'
       AND (expiry_date IS NULL OR expiry_date >= CURDATE())
       AND (usage_limit IS NULL OR used_count < usage_limit)
       ORDER BY expiry_date ASC`,
    );

    res.json({ success: true, data: vouchers });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 3. GET VOUCHER BY CODE
exports.getVoucherByCode = async (req, res) => {
  const { code } = req.params;

  try {
    const [vouchers] = await pool.execute(
      "SELECT * FROM vouchers WHERE code = ?",
      [code],
    );

    if (vouchers.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Voucher không tồn tại",
      });
    }

    res.json({ success: true, data: vouchers[0] });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 4. GET USER VOUCHERS - Danh sách vouchers của 1 user
exports.getUserVouchers = async (req, res) => {
  const { userId } = req.params;

  try {
    if (
      req.user &&
      req.user.role_name !== "admin" &&
      Number(req.user.user_id) !== Number(userId)
    ) {
      return res.status(403).json({
        success: false,
        message: "Khong co quyen xem voucher cua tai khoan nay",
      });
    }

    const [userVouchers] = await pool.execute(
      `SELECT v.*, uv.used_count AS user_used_count, uv.last_used_at
       FROM user_vouchers uv
       JOIN vouchers v ON uv.voucher_id = v.voucher_id
       WHERE uv.user_id = ?
       ORDER BY v.expiry_date ASC`,
      [userId],
    );

    res.json({ success: true, data: userVouchers });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 5. CLAIM VOUCHER - Khach hang luu voucher vao tai khoan
exports.claimVoucher = async (req, res) => {
  const { id } = req.params;
  const userId = req.user && req.user.user_id;

  if (!userId) {
    return res.status(401).json({
      success: false,
      message: "Vui long dang nhap de lay ma voucher",
    });
  }

  try {
    const [vouchers] = await pool.execute(
      `SELECT voucher_id, code, status, expiry_date, usage_limit, used_count
       FROM vouchers
       WHERE voucher_id = ?`,
      [id],
    );

    if (vouchers.length === 0) {
      return res.status(404).json({
        success: false,
        message: "Voucher khong ton tai",
      });
    }

    const voucher = vouchers[0];
    if (voucher.status !== "active") {
      return res.status(400).json({
        success: false,
        message: "Voucher khong con hoat dong",
      });
    }

    if (voucher.expiry_date && new Date(voucher.expiry_date) < new Date()) {
      return res.status(400).json({
        success: false,
        message: "Voucher da het han",
      });
    }

    if (voucher.usage_limit && voucher.used_count >= voucher.usage_limit) {
      return res.status(400).json({
        success: false,
        message: "Voucher da het luot dung",
      });
    }

    await pool.execute(
      `INSERT INTO user_vouchers (user_id, voucher_id, used_count, last_used_at)
       VALUES (?, ?, 0, NULL)
       ON DUPLICATE KEY UPDATE user_id = user_id`,
      [userId, id],
    );

    res.json({
      success: true,
      message: "Da luu voucher vao tai khoan",
      data: { voucher_id: Number(id), code: voucher.code },
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// ===== ADMIN FUNCTIONS =====

// 5. CREATE VOUCHER - Tạo mã voucher (Admin)
exports.createVoucher = async (req, res) => {
  const {
    code,
    description,
    discount_type,
    discount_value,
    min_order_amount,
    max_discount,
    usage_limit,
    expiry_date,
  } = req.body;

  try {
    // Validate input
    if (!code || !discount_type || !discount_value) {
      return res.status(400).json({
        success: false,
        message: "Vui lòng nhập đầy đủ thông tin",
      });
    }

    if (!["fixed", "percent"].includes(discount_type)) {
      return res.status(400).json({
        success: false,
        message: "Loại giảm giá không hợp lệ",
      });
    }

    const [result] = await pool.execute(
      `INSERT INTO vouchers
       (code, description, discount_type, discount_value, min_order_amount,
        max_discount, usage_limit, expiry_date, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active')`,
      [
        code.toUpperCase(),
        description || null,
        discount_type,
        discount_value,
        min_order_amount || 0,
        max_discount || null,
        usage_limit || null,
        expiry_date || null,
      ],
    );

    res.status(201).json({
      success: true,
      message: "Tạo voucher thành công",
      data: { id: result.insertId },
    });
  } catch (error) {
    if (error.code === "ER_DUP_ENTRY") {
      return res.status(400).json({
        success: false,
        message: "Mã voucher đã tồn tại",
      });
    }
    res.status(500).json({ success: false, message: error.message });
  }
};

// 6. UPDATE VOUCHER - Cập nhật voucher (Admin)
exports.updateVoucher = async (req, res) => {
  const { id } = req.params;
  const {
    description,
    discount_type,
    discount_value,
    min_order_amount,
    max_discount,
    usage_limit,
    expiry_date,
    status,
  } = req.body;

  try {
    const [result] = await pool.execute(
      `UPDATE vouchers
       SET description = ?, discount_type = ?, discount_value = ?,
           min_order_amount = ?, max_discount = ?, usage_limit = ?,
           expiry_date = ?, status = ?
       WHERE voucher_id = ?`,
      [
        description,
        discount_type,
        discount_value,
        min_order_amount || 0,
        max_discount || null,
        usage_limit || null,
        expiry_date || null,
        status || "active",
        id,
      ],
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: "Voucher không tồn tại",
      });
    }

    res.json({
      success: true,
      message: "Cập nhật voucher thành công",
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 7. DELETE VOUCHER - Xóa voucher (Admin - soft delete)
exports.deleteVoucher = async (req, res) => {
  const { id } = req.params;

  try {
    const [result] = await pool.execute(
      "UPDATE vouchers SET status = ? WHERE voucher_id = ?",
      ["inactive", id],
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: "Voucher không tồn tại",
      });
    }

    res.json({
      success: true,
      message: "Xóa voucher thành công",
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 8. GET ALL VOUCHERS (Admin) - Danh sách tất cả vouchers
exports.getAllVouchers = async (req, res) => {
  try {
    const [vouchers] = await pool.execute(
      `SELECT * FROM vouchers ORDER BY created_at DESC`,
    );

    res.json({ success: true, data: vouchers });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// 9. GET VOUCHER USAGE - Xem ai đã dùng voucher này
exports.getVoucherUsage = async (req, res) => {
  const { id } = req.params;

  try {
    const [usage] = await pool.execute(
      `SELECT u.user_id, u.full_name, u.email, o.order_id, uv.last_used_at, uv.used_count
       FROM user_vouchers uv
       JOIN users u ON uv.user_id = u.user_id
       LEFT JOIN orders o ON o.customer_id = u.user_id AND o.voucher_id = ?
       WHERE uv.voucher_id = ?
       AND uv.used_count > 0
       ORDER BY uv.last_used_at DESC`,
      [id, id],
    );

    res.json({ success: true, data: usage });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
