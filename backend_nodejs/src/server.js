const express = require("express");
const cors = require("cors");
const path = require("path");
require("dotenv").config();

const pool = require("./config/db");

const app = express();

app.use(cors());
app.use(express.json());

const authRoutes = require("./routes/auth.routes");
const userRoutes = require("./routes/user.routes");
const categoryRoutes = require("./routes/category.routes");
const productRoutes = require("./routes/product.routes");
const cartRoutes = require("./routes/cart.routes");
const orderRoutes = require("./routes/order.routes");
const inventoryRoutes = require("./routes/inventory.routes");
const uploadRoutes = require("./routes/upload.routes");
const reportRoutes = require("./routes/report.routes");
const performanceRoutes = require("./routes/performance.routes");
const reviewRoutes = require("./routes/review.routes");
const workShiftRoutes = require("./routes/workShift.routes");
const employeeScheduleRoutes = require("./routes/employeeSchedule.routes");
const voucherRoutes = require("./routes/voucher.routes");
const myOrderRoutes = require("./routes/myOrder.routes");
const paymentRoutes = require("./routes/payment.routes");
const pointRoutes = require("./routes/point.routes");

app.use("/api/auth", authRoutes);
app.use("/api/users", userRoutes);
app.use("/api/categories", categoryRoutes);
app.use("/api/products", productRoutes);
app.use("/cart", cartRoutes);
app.use("/api/cart", cartRoutes);
app.use("/api/carts", cartRoutes);
app.use("/api/orders", orderRoutes);
app.use("/orders", orderRoutes);
app.use("/my-orders", myOrderRoutes);
app.use("/api/inventory", inventoryRoutes);
app.use("/api/uploads", uploadRoutes);
app.use("/api/reports", reportRoutes);
app.use("/api/performance", performanceRoutes);
app.use("/api/reviews", reviewRoutes);
app.use("/api/work-shifts", workShiftRoutes);
app.use("/api/employee-schedules", employeeScheduleRoutes);
app.use("/api/vouchers", voucherRoutes);
app.use("/api/payments", paymentRoutes);
app.use("/api/webhook", paymentRoutes);
app.use("/api/points", pointRoutes);
app.use("/uploads", express.static(path.join(__dirname, "..", "uploads")));

app.get("/", (req, res) => {
  res.json({
    success: true,
    message: "Mini Market API is running",
  });
});

app.get("/api/test-db", async (req, res) => {
  try {
    const [rows] = await pool.execute("SELECT * FROM roles");

    res.json({
      success: true,
      message: "Kết nối database thành công",
      data: rows,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Không kết nối được database",
      error: error.message,
    });
  }
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server đang chạy tại http://localhost:${PORT}`);
  console.log(
    "Điện thoại thật (cùng Wi-Fi): dùng IP máy tính, ví dụ http://192.168.x.x:" +
      PORT,
  );
});
