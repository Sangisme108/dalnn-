const express = require("express");
const pool = require("../config/db");

const router = express.Router();

const paidOrderCondition =
  "(o.payment_status IN ('paid', 'success') OR o.status IN ('completed', 'Hoàn thành', 'hoàn thành') OR o.order_status = 'completed')";

async function requireAdmin(req, res, next) {
  try {
    const userId = Number(req.get("x-user-id"));
    if (!userId) {
      return res.status(401).json({
        success: false,
        message: "Thieu thong tin admin",
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
        message: "Chi admin duoc xem hieu suat san pham",
      });
    }
    next();
  } catch (error) {
    return res.status(403).json({
      success: false,
      message: "Khong kiem tra duoc quyen admin",
      error: error.message,
    });
  }
}

router.use(requireAdmin);

function rangeConfig(rawRange, rawMonth) {
  const range = (rawRange || "30d").toString();
  if (range === "today") {
    return {
      range,
      chartGranularity: "day",
      dateCondition: "AND DATE(o.created_at) = CURDATE()",
      params: [],
    };
  }
  if (range === "7days" || range === "7d") {
    return {
      range: "7days",
      chartGranularity: "day",
      dateCondition:
        "AND DATE(o.created_at) >= DATE_SUB(CURDATE(), INTERVAL 6 DAY) AND DATE(o.created_at) <= CURDATE()",
      params: [],
    };
  }
  if (range === "month") {
    const month = /^\d{4}-\d{2}$/.test((rawMonth || "").toString())
      ? rawMonth.toString()
      : new Date().toISOString().slice(0, 7);
    return {
      range,
      month,
      chartGranularity: "day",
      dateCondition:
        "AND o.created_at >= STR_TO_DATE(?, '%Y-%m-%d') AND o.created_at < DATE_ADD(STR_TO_DATE(?, '%Y-%m-%d'), INTERVAL 1 MONTH)",
      params: [`${month}-01`, `${month}-01`],
    };
  }
  return {
    range: "30days",
    chartGranularity: "day",
    dateCondition:
      "AND DATE(o.created_at) >= DATE_SUB(CURDATE(), INTERVAL 29 DAY) AND DATE(o.created_at) <= CURDATE()",
    params: [],
  };
}

function productSelect(dateCondition) {
  return `
    SELECT
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
      sales.last_order_at,
      CASE
        WHEN sales.last_order_at IS NULL THEN 999
        ELSE DATEDIFF(CURDATE(), DATE(sales.last_order_at))
      END AS days_without_order
    FROM products p
    JOIN categories c ON c.category_id = p.category_id
    LEFT JOIN (
      SELECT
        oi.product_id,
        SUM(oi.quantity) AS total_quantity_sold,
        SUM(oi.subtotal) AS total_revenue,
        COUNT(DISTINCT o.order_id) AS orders_count,
        MAX(o.created_at) AS last_order_at
      FROM order_items oi
      JOIN orders o ON o.order_id = oi.order_id
      WHERE ${paidOrderCondition}
        ${dateCondition}
      GROUP BY oi.product_id
    ) sales ON sales.product_id = p.product_id
    WHERE p.status <> 'deleted'
  `;
}

function mapProduct(row) {
  return {
    product_id: row.product_id,
    product_name: row.product_name,
    barcode: row.barcode,
    image_url: row.image_url,
    category_name: row.category_name,
    sale_price: Number(row.sale_price || 0),
    unit: row.unit || "sp",
    current_stock: Number(row.current_stock || 0),
    min_stock: Number(row.min_stock || 0),
    total_quantity_sold: Number(row.total_quantity_sold || 0),
    total_revenue: Number(row.total_revenue || 0),
    orders_count: Number(row.orders_count || 0),
    days_without_order: Number(row.days_without_order || 0),
  };
}

function buildSuggestions(topProducts, highStockProducts, slowProducts) {
  const suggestions = [];
  for (const product of slowProducts.slice(0, 3)) {
    if (product.current_stock >= 50) {
      suggestions.push({
        type: "clearance",
        title: `${product.product_name} ton kho cao nhung ban cham`,
        message: "Nen tao voucher hoac chuong trinh xa kho cho san pham nay.",
        severity: "warning",
      });
    }
  }
  for (const product of topProducts.slice(0, 3)) {
    if (product.current_stock <= Math.max(product.min_stock, 10)) {
      suggestions.push({
        type: "restock",
        title: `${product.product_name} dang ban tot, nen nhap them hang`,
        message: "San pham co doanh so cao trong ky loc va ton kho dang thap.",
        severity: "success",
      });
    }
  }
  if (suggestions.length === 0) {
    suggestions.push({
      type: "stable",
      title: "Hieu suat san pham dang on dinh",
      message: "Chua phat hien san pham can xu ly gap theo ton kho va doanh so.",
      severity: "info",
    });
  }
  return suggestions;
}

router.get("/dashboard", async (req, res) => {
  const config = rangeConfig(req.query.range, req.query.month);
  console.log("[performance] dashboard request", {
    range: config.range,
    month: config.month || null,
  });

  try {
    const [overviewRows] = await pool.execute(
      `SELECT
         COALESCE(SUM(o.final_amount), 0) AS total_revenue,
         COUNT(DISTINCT o.order_id) AS total_orders,
         COALESCE(SUM(oi.quantity), 0) AS total_products_sold,
         COALESCE(AVG(o.final_amount), 0) AS average_order_value
       FROM orders o
       LEFT JOIN order_items oi ON oi.order_id = o.order_id
       WHERE ${paidOrderCondition}
         ${config.dateCondition}`,
      config.params,
    );

    const [stockRows] = await pool.execute(
      `SELECT COALESCE(SUM(stock), 0) AS total_stock
       FROM products
       WHERE status <> 'deleted'`,
    );

    const [productRows] = await pool.execute(
      `${productSelect(config.dateCondition)}
       ORDER BY total_quantity_sold DESC, total_revenue DESC, p.product_name ASC`,
      config.params,
    );

    const [chartRows] = await pool.execute(
      `SELECT
         DATE_FORMAT(o.created_at, '%Y-%m-%d') AS period,
         COALESCE(SUM(o.final_amount), 0) AS revenue,
         COUNT(DISTINCT o.order_id) AS orders_count
       FROM orders o
       WHERE ${paidOrderCondition}
         ${config.dateCondition}
       GROUP BY DATE_FORMAT(o.created_at, '%Y-%m-%d')
       ORDER BY period ASC`,
      config.params,
    );

    const products = productRows.map(mapProduct);
    const topProducts = products
      .filter((product) => product.total_quantity_sold > 0)
      .slice(0, 10);
    const topRevenueProducts = products
      .filter((product) => product.total_revenue > 0)
      .sort((a, b) => b.total_revenue - a.total_revenue)
      .slice(0, 10);
    const highStockProducts = products
      .filter((product) => product.current_stock > 50)
      .sort((a, b) => b.current_stock - a.current_stock)
      .slice(0, 10);
    const slowProducts = products
      .filter((product) => product.total_quantity_sold < 5)
      .sort((a, b) => b.days_without_order - a.days_without_order)
      .slice(0, 10);

    const overview = overviewRows[0] || {};
    console.log("[performance] dashboard result", {
      products: products.length,
      chart: chartRows.length,
      top: topProducts.length,
      topRevenue: topRevenueProducts.length,
      highStock: highStockProducts.length,
      slow: slowProducts.length,
    });

    res.json({
      success: true,
      data: {
        filter: {
          range: config.range,
          month: config.month || null,
          chart_granularity: config.chartGranularity,
        },
        overview: {
          total_revenue: Number(overview.total_revenue || 0),
          total_orders: Number(overview.total_orders || 0),
          total_products_sold: Number(overview.total_products_sold || 0),
          total_stock: Number((stockRows[0] || {}).total_stock || 0),
          average_order_value: Number(overview.average_order_value || 0),
        },
        top_products: topProducts,
        top_revenue_products: topRevenueProducts,
        high_stock_products: highStockProducts,
        slow_products: slowProducts,
        suggestions: buildSuggestions(topProducts, highStockProducts, slowProducts),
        revenue_chart: chartRows.map((row) => ({
          period: row.period,
          revenue: Number(row.revenue || 0),
          orders_count: Number(row.orders_count || 0),
        })),
      },
    });
  } catch (error) {
    console.error("[performance] dashboard error", error);
    res.status(500).json({
      success: false,
      message: "Loi lay dashboard hieu suat san pham",
      error: error.message,
    });
  }
});

module.exports = router;
