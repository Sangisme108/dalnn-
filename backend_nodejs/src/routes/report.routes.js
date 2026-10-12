const express = require("express");
const pool = require("../config/db");

const router = express.Router();

async function requireAdmin(req, res, next) {
  try {
    const userId = Number(req.get("x-user-id"));
    if (!userId) {
      return res.status(401).json({
        success: false,
        message: "Thiếu thông tin admin",
      });
    }

    const [users] = await pool.execute(
      `SELECT u.user_id
       FROM users u
       JOIN roles r ON r.role_id = u.role_id
       WHERE u.user_id = ? AND r.role_name = 'admin' AND u.status = 'active'`,
      [userId],
    );

    if (users.length === 0) {
      return res.status(403).json({
        success: false,
        message: "Chỉ admin được xem báo cáo",
      });
    }
    next();
  } catch (error) {
    return res.status(403).json({
      success: false,
      message: "Không kiểm tra được quyền admin",
      error: error.message,
    });
  }
}

const paidOrderCondition = "o.payment_status IN ('paid', 'success')";

const latestImportPriceSql = `
  SELECT
    ii.barcode,
    COALESCE(
      (
        SELECT il.import_price
        FROM inventory_logs il
        WHERE il.inventory_item_id = ii.inventory_item_id
          AND il.action = 'import'
          AND il.import_price IS NOT NULL
        ORDER BY il.created_at DESC, il.log_id DESC
        LIMIT 1
      ),
      ii.import_price
    ) AS import_price
  FROM inventory_items ii
`;

router.use(requireAdmin);

function groupRevenueByPeriod(periodExpr) {
  return `SELECT
         ${periodExpr} AS period,
         COALESCE(SUM(o.final_amount), 0) AS revenue,
         COUNT(DISTINCT o.order_id) AS orders_count
       FROM orders o
       WHERE ${paidOrderCondition}
       GROUP BY period
       ORDER BY period ASC`;
}

router.get("/revenue", async (req, res) => {
  try {
    const [summaryRows] = await pool.execute(
      `SELECT
         COALESCE(SUM(oi.subtotal), 0) AS total_revenue,
         COALESCE(MAX(order_summary.total_net_revenue), 0) AS total_net_revenue,
         COALESCE(MAX(order_summary.total_discount), 0) AS total_discount,
         COALESCE(MAX(order_summary.average_order_value), 0) AS average_order_value,
         COUNT(DISTINCT o.order_id) AS total_orders,
         COALESCE(SUM(oi.quantity), 0) AS total_products_sold,
         COALESCE(SUM(CASE WHEN cost.import_price IS NULL THEN 1 ELSE 0 END), 0) AS missing_cost_lines,
         COALESCE(SUM(oi.subtotal - (oi.quantity * cost.import_price)), 0) AS total_profit
       FROM orders o
       JOIN order_items oi ON oi.order_id = o.order_id
       JOIN products p ON p.product_id = oi.product_id
       LEFT JOIN (${latestImportPriceSql}) cost ON cost.barcode = p.barcode
       CROSS JOIN (
         SELECT
           COALESCE(SUM(final_amount), 0) AS total_net_revenue,
           COALESCE(SUM(GREATEST(total_amount - final_amount, 0)), 0) AS total_discount,
           COALESCE(AVG(final_amount), 0) AS average_order_value
         FROM orders o
         WHERE ${paidOrderCondition}
       ) order_summary
       WHERE ${paidOrderCondition}`,
    );

    const [hourRows] = await pool.execute(
      `SELECT
         HOUR(o.created_at) AS period,
         COALESCE(SUM(o.final_amount), 0) AS revenue,
         COUNT(DISTINCT o.order_id) AS orders_count
       FROM orders o
       WHERE ${paidOrderCondition}
         AND DATE(o.created_at) = CURDATE()
       GROUP BY HOUR(o.created_at)
       ORDER BY period ASC`,
    );

    const [timeRows] = await pool.execute(
      `SELECT
         DATE_FORMAT(o.created_at, '%Y-%m-%d') AS period,
         COALESCE(SUM(o.final_amount), 0) AS revenue,
         COUNT(DISTINCT o.order_id) AS orders_count
       FROM orders o
       WHERE ${paidOrderCondition}
       GROUP BY DATE_FORMAT(o.created_at, '%Y-%m-%d')
       ORDER BY period ASC`,
    );

    // Month buckets
    const monthExpr = "DATE_FORMAT(o.created_at, '%Y-%m-01')";
    const [monthRows] = await pool.execute(groupRevenueByPeriod(monthExpr));

    // Year buckets
    const yearExpr = "DATE_FORMAT(o.created_at, '%Y-01-01')";
    const [yearRows] = await pool.execute(groupRevenueByPeriod(yearExpr));

    const summary = summaryRows[0] || {};
    const totalProductsSold = Number(summary.total_products_sold || 0);
    const missingCostLines = Number(summary.missing_cost_lines || 0);
    const totalProfit =
      totalProductsSold > 0 && missingCostLines > 0
        ? null
        : Number(summary.total_profit || 0);

    res.json({
      success: true,
      data: {
        total_revenue: Number(summary.total_revenue || 0),
        total_net_revenue: Number(summary.total_net_revenue || 0),
        total_discount: Number(summary.total_discount || 0),
        average_order_value: Number(summary.average_order_value || 0),
        total_profit: totalProfit,
        profit_note:
          totalProfit == null
            ? "Chưa đủ dữ liệu tính lợi nhuận: một số sản phẩm đã bán chưa có import_price."
            : null,
        total_orders: Number(summary.total_orders || 0),
        total_products_sold: totalProductsSold,
        revenue_by_hour_today: hourRows.map((row) => ({
          period: Number(row.period || 0),
          revenue: Number(row.revenue || 0),
          orders_count: Number(row.orders_count || 0),
        })),
        revenue_by_time: timeRows.map((row) => ({
          period: row.period,
          revenue: Number(row.revenue || 0),
          orders_count: Number(row.orders_count || 0),
        })),
        revenue_by_month: monthRows.map((row) => ({
          period: row.period,
          revenue: Number(row.revenue || 0),
          orders_count: Number(row.orders_count || 0),
        })),
        revenue_by_year: yearRows.map((row) => ({
          period: row.period,
          revenue: Number(row.revenue || 0),
          orders_count: Number(row.orders_count || 0),
        })),
      },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Lỗi lấy báo cáo doanh thu",
      error: error.message,
    });
  }
});

router.get("/product-performance", async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT
         p.product_id,
         p.product_name,
         p.barcode,
         p.image_url,
         p.price AS sale_price,
         p.unit,
         p.stock AS current_stock,
         p.min_stock,
         c.category_name,
         COALESCE(sales.total_quantity_sold, 0) AS total_quantity_sold,
         COALESCE(sales.total_revenue, 0) AS total_revenue,
         COALESCE(sales.orders_count, 0) AS orders_count,
         CASE
           WHEN cost.import_price IS NULL AND COALESCE(sales.total_quantity_sold, 0) > 0
             THEN NULL
           ELSE COALESCE(sales.total_revenue, 0) - (COALESCE(sales.total_quantity_sold, 0) * COALESCE(cost.import_price, 0))
         END AS total_profit,
         CASE
           WHEN COALESCE(sales.total_quantity_sold, 0) = 0 THEN 0
           ELSE COALESCE(sales.total_revenue, 0) / COALESCE(sales.total_quantity_sold, 1)
         END AS average_sale_price,
         cost.import_price,
         CASE
           WHEN COALESCE(sales.total_quantity_sold, 0) + p.stock = 0 THEN 0
           ELSE (COALESCE(sales.total_quantity_sold, 0) * 100.0) / (COALESCE(sales.total_quantity_sold, 0) + p.stock)
         END AS sell_through_rate
       FROM products p
       JOIN categories c ON c.category_id = p.category_id
       LEFT JOIN (${latestImportPriceSql}) cost ON cost.barcode = p.barcode
       LEFT JOIN (
         SELECT
           oi.product_id,
           SUM(oi.quantity) AS total_quantity_sold,
           SUM(oi.subtotal) AS total_revenue,
           COUNT(DISTINCT o.order_id) AS orders_count
         FROM order_items oi
         JOIN orders o ON o.order_id = oi.order_id
         WHERE ${paidOrderCondition}
         GROUP BY oi.product_id
       ) sales ON sales.product_id = p.product_id
       WHERE p.status <> 'deleted'
       ORDER BY total_quantity_sold DESC, total_revenue DESC, p.product_name ASC`,
    );

    res.json({
      success: true,
      data: rows.map((row) => ({
        product_id: row.product_id,
        product_name: row.product_name,
        barcode: row.barcode,
        image_url: row.image_url,
        category_name: row.category_name,
        sale_price: Number(row.sale_price || 0),
        unit: row.unit || "sp",
        total_quantity_sold: Number(row.total_quantity_sold || 0),
        total_revenue: Number(row.total_revenue || 0),
        orders_count: Number(row.orders_count || 0),
        total_profit:
          row.total_profit == null ? null : Number(row.total_profit || 0),
        average_sale_price: Number(row.average_sale_price || 0),
        current_stock: Number(row.current_stock || 0),
        min_stock: Number(row.min_stock || 0),
        import_price:
          row.import_price == null ? null : Number(row.import_price || 0),
        sell_through_rate: Number(row.sell_through_rate || 0),
      })),
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Lỗi lấy báo cáo hiệu suất sản phẩm",
      error: error.message,
    });
  }
});

module.exports = router;
