const express = require("express");
const pool = require("../config/db");

const router = express.Router();

function toInventoryItem(row) {
  return {
    id: row.barcode,
    inventory_item_id: row.inventory_item_id,
    barcode: row.barcode,
    name: row.item_name,
    item_name: row.item_name,
    image_url: row.image_url,
    price: Number(row.price),
    import_price: row.import_price == null ? null : Number(row.import_price),
    importPrice: row.import_price == null ? null : Number(row.import_price),
    unit: row.unit || "sp",
    stockQuantity: row.stock,
    stock: row.stock,
    category_id: row.category_id == null ? null : Number(row.category_id),
    categoryId: row.category_id == null ? null : Number(row.category_id),
    status: row.status,
  };
}

router.get("/items", async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT *
       FROM inventory_items
       WHERE status <> 'deleted'
       ORDER BY inventory_item_id DESC`,
    );
    res.json({ success: true, data: rows.map(toInventoryItem) });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Lỗi lấy hàng trong kho",
      error: error.message,
    });
  }
});

router.post("/items", async (req, res) => {
  console.log("HIT POST /api/inventory/items", {
    path: req.path,
    body: req.body,
  });
  try {
    const {
      barcode,
      item_name,
      name,
      image_url,
      price,
      import_price,
      importPrice,
      unit,
      stock,
      stockQuantity,
      category_id,
      categoryId,
    } = req.body;

    console.log("POST /api/inventory/items body:", {
      barcode,
      item_name,
      price,
      category_id,
      categoryId,
    });

    const itemName = item_name || name;
    if (!barcode || !itemName || price == null) {
      return res.status(400).json({
        success: false,
        message: "Vui lòng nhập barcode, item_name, price",
      });
    }

    // Nếu client gửi categoryId/category_id mà rỗng/null thì chặn luôn.
    // Tránh trường hợp inventory_items được tạo nhưng category_id vẫn NULL.
    // const nextCategoryId = category_id ?? categoryId;
    // if (nextCategoryId == null) {
    //   return res.status(400).json({
    //     success: false,
    //     message: "Vui lòng nhập category_id",
    //   });
    // }
    const nextImportPrice = import_price ?? importPrice;
    if (nextImportPrice != null && Number(nextImportPrice) <= 0) {
      return res
        .status(400)
        .json({ success: false, message: "Giá nhập phải lớn hơn 0" });
    }

    if (category_id == null && categoryId == null) {
      return res
        .status(400)
        .json({ success: false, message: "Vui lòng nhập category_id" });
    }

    const nextCategoryId = category_id ?? categoryId;

    const [result] = await pool.execute(
      `INSERT INTO inventory_items (barcode, item_name, image_url, price, import_price, unit, stock, category_id, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active')`,
      [
        barcode,
        itemName,
        image_url || null,
        Number(price),
        nextImportPrice == null ? null : Number(nextImportPrice),
        unit || "sp",
        Number(stock ?? stockQuantity ?? 0),
        Number(nextCategoryId),
      ],
    );

    const [rows] = await pool.execute(
      "SELECT * FROM inventory_items WHERE inventory_item_id = ?",
      [result.insertId],
    );
    res.status(201).json({
      success: true,
      message: "Đã thêm hàng vào kho",
      data: toInventoryItem(rows[0]),
    });
  } catch (error) {
    const status = error.code === "ER_DUP_ENTRY" ? 409 : 500;
    res.status(status).json({
      success: false,
      message: "Lỗi thêm hàng vào kho",
      error: error.message,
    });
  }
});

router.put("/items/:id", async (req, res) => {
  try {
    const {
      barcode,
      item_name,
      name,
      image_url,
      price,
      import_price,
      importPrice,
      unit,
      stock,
      stockQuantity,
      category_id,
      categoryId,
      status,
    } = req.body;
    const nextImportPrice = import_price ?? importPrice;
    if (nextImportPrice != null && Number(nextImportPrice) <= 0) {
      return res
        .status(400)
        .json({ success: false, message: "Giá nhập phải lớn hơn 0" });
    }
    await pool.execute(
      `UPDATE inventory_items
       SET barcode = COALESCE(?, barcode),
           item_name = COALESCE(?, item_name),
           image_url = ?,
           price = COALESCE(?, price),
           import_price = COALESCE(?, import_price),
           unit = COALESCE(?, unit),
           stock = COALESCE(?, stock),
           category_id = COALESCE(?, category_id),
           status = COALESCE(?, status)
       WHERE inventory_item_id = ? OR barcode = ?`,
      [
        barcode || null,
        item_name || name || null,
        image_url ?? null,
        price == null ? null : Number(price),
        nextImportPrice == null ? null : Number(nextImportPrice),
        unit || null,
        stock == null && stockQuantity == null
          ? null
          : Number(stock ?? stockQuantity),
        category_id == null && categoryId == null
          ? null
          : Number(category_id ?? categoryId),
        status || null,
        req.params.id,
        req.params.id,
      ],
    );
    const [rows] = await pool.execute(
      "SELECT * FROM inventory_items WHERE inventory_item_id = ? OR barcode = ?",
      [req.params.id, req.params.id],
    );
    if (rows.length === 0) {
      return res
        .status(404)
        .json({ success: false, message: "Không tìm thấy hàng trong kho" });
    }
    res.json({
      success: true,
      message: "Đã cập nhật hàng trong kho",
      data: toInventoryItem(rows[0]),
    });
  } catch (error) {
    const status = error.code === "ER_DUP_ENTRY" ? 409 : 500;
    res.status(status).json({
      success: false,
      message: "Lỗi cập nhật hàng trong kho",
      error: error.message,
    });
  }
});

router.get("/logs", async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT il.*, ii.item_name, ii.barcode, ii.unit, p.product_name, u.full_name AS employee_name
       FROM inventory_logs il
       JOIN inventory_items ii ON ii.inventory_item_id = il.inventory_item_id
       LEFT JOIN products p ON p.product_id = il.product_id
       JOIN users u ON u.user_id = il.employee_id
       ORDER BY il.created_at DESC`,
    );
    res.json({ success: true, data: rows });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Lỗi lấy lịch sử kho",
      error: error.message,
    });
  }
});

router.get("/cost/:barcode", async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT
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
       WHERE ii.barcode = ? OR CAST(ii.inventory_item_id AS CHAR) = ?
       LIMIT 1`,
      [req.params.barcode, req.params.barcode],
    );
    if (rows.length === 0 || rows[0].import_price == null) {
      return res.json({ success: true, data: { import_price: null } });
    }
    res.json({
      success: true,
      data: { import_price: Number(rows[0].import_price) },
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Lỗi lấy giá nhập",
      error: error.message,
    });
  }
});

router.post("/import", async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const {
      inventory_item_id,
      employee_id,
      quantity,
      import_price,
      importPrice,
      note,
    } = req.body;
    if (!inventory_item_id || !employee_id || Number(quantity) <= 0) {
      return res.status(400).json({
        success: false,
        message: "Vui lòng nhập inventory_item_id, employee_id, quantity",
      });
    }
    const nextImportPrice = import_price ?? importPrice;
    if (nextImportPrice == null || Number(nextImportPrice) <= 0) {
      return res
        .status(400)
        .json({ success: false, message: "Giá nhập phải lớn hơn 0" });
    }

    await connection.beginTransaction();
    const [items] = await connection.execute(
      "SELECT inventory_item_id FROM inventory_items WHERE inventory_item_id = ? OR barcode = ? FOR UPDATE",
      [inventory_item_id, inventory_item_id],
    );
    if (items.length === 0) throw new Error("Không tìm thấy hàng trong kho");
    const itemId = Number(items[0].inventory_item_id);
    await connection.execute(
      "UPDATE inventory_items SET stock = stock + ?, import_price = ? WHERE inventory_item_id = ?",
      [Number(quantity), Number(nextImportPrice), itemId],
    );
    await connection.execute(
      `INSERT INTO inventory_logs (inventory_item_id, product_id, employee_id, action, quantity, import_price, note)
       VALUES (?, NULL, ?, 'import', ?, ?, ?)`,
      [
        itemId,
        Number(employee_id),
        Number(quantity),
        Number(nextImportPrice),
        note || null,
      ],
    );
    await connection.commit();
    res.json({ success: true, message: "Đã nhập kho" });
  } catch (error) {
    await connection.rollback();
    res
      .status(500)
      .json({ success: false, message: "Lỗi nhập kho", error: error.message });
  } finally {
    connection.release();
  }
});

router.post("/adjust", async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const { inventory_item_id, employee_id, actual_quantity, note } = req.body;
    if (!inventory_item_id || !employee_id || Number(actual_quantity) < 0) {
      return res.status(400).json({
        success: false,
        message:
          "Vui lòng nhập inventory_item_id, employee_id, actual_quantity",
      });
    }

    await connection.beginTransaction();
    const [items] = await connection.execute(
      "SELECT inventory_item_id, stock FROM inventory_items WHERE inventory_item_id = ? OR barcode = ? FOR UPDATE",
      [inventory_item_id, inventory_item_id],
    );
    if (items.length === 0) {
      throw new Error("Không tìm thấy hàng trong kho");
    }

    const beforeStock = Number(items[0].stock);
    const actualQuantity = Number(actual_quantity);
    const difference = actualQuantity - beforeStock;

    await connection.execute(
      "UPDATE inventory_items SET stock = ? WHERE inventory_item_id = ?",
      [actualQuantity, Number(items[0].inventory_item_id)],
    );
    await connection.execute(
      `INSERT INTO inventory_logs (inventory_item_id, product_id, employee_id, action, quantity, note)
       VALUES (?, NULL, ?, 'adjust', ?, ?)`,
      [
        Number(items[0].inventory_item_id),
        Number(employee_id),
        difference,
        note || `Kiểm kê: ${beforeStock} -> ${actualQuantity}`,
      ],
    );
    await connection.commit();
    res.json({
      success: true,
      message: "Đã điều chỉnh tồn kho",
      data: { beforeStock, actualQuantity, difference },
    });
  } catch (error) {
    await connection.rollback();
    res.status(500).json({
      success: false,
      message: "Lỗi kiểm kê kho",
      error: error.message,
    });
  } finally {
    connection.release();
  }
});

router.post("/export", async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const { inventory_item_id, product_id, employee_id, quantity, note } =
      req.body;
    if (!inventory_item_id || !employee_id || Number(quantity) <= 0) {
      return res.status(400).json({
        success: false,
        message: "Vui lòng nhập inventory_item_id, employee_id, quantity",
      });
    }

    await connection.beginTransaction();
    const [items] = await connection.execute(
      "SELECT inventory_item_id, stock FROM inventory_items WHERE inventory_item_id = ? OR barcode = ? FOR UPDATE",
      [inventory_item_id, inventory_item_id],
    );
    if (items.length === 0) throw new Error("Không tìm thấy hàng trong kho");
    if (Number(items[0].stock) < Number(quantity))
      throw new Error("Không đủ tồn kho");

    await connection.execute(
      "UPDATE inventory_items SET stock = stock - ? WHERE inventory_item_id = ?",
      [Number(quantity), Number(items[0].inventory_item_id)],
    );
    await connection.execute(
      `INSERT INTO inventory_logs (inventory_item_id, product_id, employee_id, action, quantity, note)
       VALUES (?, ?, ?, 'export', ?, ?)`,
      [
        Number(items[0].inventory_item_id),
        product_id ? Number(product_id) : null,
        Number(employee_id),
        -Number(quantity),
        note || "Đưa hàng lên kệ",
      ],
    );
    await connection.commit();
    res.json({ success: true, message: "Đã xuất hàng khỏi kho" });
  } catch (error) {
    await connection.rollback();
    res
      .status(500)
      .json({ success: false, message: "Lỗi xuất kho", error: error.message });
  } finally {
    connection.release();
  }
});

module.exports = router;
