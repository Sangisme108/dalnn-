const express = require('express');
const pool = require('../config/db');

const router = express.Router();

async function getLatestImportPrice(barcode) {
  if (!barcode) return null;
  const [rows] = await pool.execute(
    `SELECT COALESCE(
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
    [barcode, barcode]
  );
  if (rows.length === 0 || rows[0].import_price == null) return null;
  return Number(rows[0].import_price);
}

function toProduct(row) {
  return {
    id: String(row.product_id),
    product_id: row.product_id,
    name: row.product_name,
    product_name: row.product_name,
    barcode: row.barcode,
    description: row.description,
    image_url: row.image_url,
    price: Number(row.price),
    unit: row.unit || 'sp',
    stockQuantity: row.stock,
    stock: row.stock,
    min_stock: row.min_stock,
    category_id: row.category_id,
    category_name: row.category_name,
    status: row.status,
  };
}

router.get('/', async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT p.*, c.category_name
       FROM products p
       JOIN categories c ON c.category_id = p.category_id
       WHERE p.status <> 'deleted'
       ORDER BY p.product_id DESC`
    );
    res.json({ success: true, data: rows.map(toProduct) });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi lấy sản phẩm', error: error.message });
  }
});

router.get('/scan/:code', async (req, res) => {
  try {
    const code = req.params.code.trim();
    if (!code) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập mã vạch / mã nội bộ' });
    }

    const [products] = await pool.execute(
      `SELECT p.*, c.category_name
       FROM products p
       JOIN categories c ON c.category_id = p.category_id
       WHERE p.barcode = ? AND p.status <> 'deleted'
       LIMIT 1`,
      [code]
    );
    if (products.length > 0) {
      const product = toProduct(products[0]);
      return res.json({
        success: true,
        data: {
          ...product,
          stock_quantity: product.stock,
          type: 'product',
          product,
        },
      });
    }

    const [inventoryItems] = await pool.execute(
      `SELECT *
       FROM inventory_items
       WHERE barcode = ? AND status <> 'deleted'
       LIMIT 1`,
      [code]
    );
    if (inventoryItems.length > 0) {
      const item = inventoryItems[0];
      return res.json({
        success: true,
        data: {
          type: 'inventory_item',
          inventory_item: {
            id: item.barcode,
            inventory_item_id: item.inventory_item_id,
            barcode: item.barcode,
            name: item.item_name,
            item_name: item.item_name,
            image_url: item.image_url,
            price: Number(item.price),
            import_price: item.import_price == null ? null : Number(item.import_price),
            unit: item.unit || 'sp',
            stock: item.stock,
            stockQuantity: item.stock,
            status: item.status,
          },
        },
      });
    }

    res.status(404).json({ success: false, message: 'Không tìm thấy mã vạch / mã nội bộ' });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi quét mã sản phẩm', error: error.message });
  }
});

router.get('/check-code/:code', async (req, res) => {
  try {
    const code = (req.params.code || '').trim();
    if (!code) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập mã cần kiểm tra' });
    }

    const [products] = await pool.execute(
      'SELECT product_id FROM products WHERE barcode = ? LIMIT 1',
      [code]
    );

    const [inventoryItems] = await pool.execute(
      'SELECT inventory_item_id FROM inventory_items WHERE barcode = ? LIMIT 1',
      [code]
    );

    res.json({
      success: true,
      data: {
        exists: products.length > 0 || inventoryItems.length > 0,
      },
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi kiểm tra mã vạch / mã nội bộ', error: error.message });
  }
});

router.post('/generate-code', async (req, res) => {
  try {
    const { prefix } = req.body;
    let codePrefix = String(prefix || 'SP').trim().toUpperCase();
    codePrefix = codePrefix.replace(/[^A-Z]/g, '').slice(0, 8) || 'SP';

    for (let attempt = 0; attempt < 20; attempt += 1) {
      const code = `${codePrefix}${Date.now() + attempt}`;
      const [existingProducts] = await pool.execute(
        'SELECT product_id FROM products WHERE barcode = ? LIMIT 1',
        [code]
      );
      if (existingProducts.length > 0) continue;

      const [existingInventory] = await pool.execute(
        'SELECT inventory_item_id FROM inventory_items WHERE barcode = ? LIMIT 1',
        [code]
      );
      if (existingInventory.length === 0) {
        return res.json({ success: true, data: { code } });
      }
    }

    res.status(409).json({ success: false, message: 'Không tạo được mã mới không trùng' });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi tạo mã nội bộ', error: error.message });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const [rows] = await pool.execute(
      `SELECT p.*, c.category_name
       FROM products p
       JOIN categories c ON c.category_id = p.category_id
       WHERE p.product_id = ? AND p.status <> 'deleted'`,
      [req.params.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy sản phẩm' });
    }
    res.json({ success: true, data: toProduct(rows[0]) });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi lấy sản phẩm', error: error.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const {
      product_name,
      name,
      barcode,
      description,
      image_url,
      price,
      unit,
      stock,
      stockQuantity,
      min_stock,
      category_id,
    } = req.body;

    const productName = product_name || name;
    const productBarcode = barcode || `P${Date.now()}`;
    const productStock = Number(stock ?? stockQuantity ?? 0);
    const productPrice = Number(price);

    if (!productName || price == null || !category_id) {
      return res.status(400).json({
        success: false,
        message: 'Vui lòng nhập product_name, price, category_id',
      });
    }
    if (productPrice <= 0) {
      return res.status(400).json({ success: false, message: 'Giá bán phải lớn hơn 0' });
    }
    const [existingCodes] = await pool.execute(
      'SELECT product_id FROM products WHERE barcode = ? LIMIT 1',
      [productBarcode]
    );
    if (existingCodes.length > 0) {
      return res.status(409).json({ success: false, message: 'Mã vạch / mã nội bộ đã tồn tại' });
    }
    const importPrice = await getLatestImportPrice(productBarcode);
    if (importPrice != null && productPrice < importPrice) {
      return res.status(400).json({ success: false, message: 'Giá bán không được nhỏ hơn giá nhập' });
    }

    const [result] = await pool.execute(
      `INSERT INTO products
       (product_name, barcode, description, image_url, price, unit, stock, min_stock, category_id, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active')`,
      [
        productName,
        productBarcode,
        description || null,
        image_url || null,
        productPrice,
        unit || 'sp',
        productStock,
        Number(min_stock ?? 10),
        Number(category_id),
      ]
    );

    const [rows] = await pool.execute(
      `SELECT p.*, c.category_name
       FROM products p
       JOIN categories c ON c.category_id = p.category_id
       WHERE p.product_id = ?`,
      [result.insertId]
    );
    res.status(201).json({
      success: true,
      message: 'Đã thêm sản phẩm',
      warning: importPrice == null ? 'Sản phẩm chưa có giá nhập, không thể kiểm tra giá vốn' : null,
      data: toProduct(rows[0]),
    });
  } catch (error) {
    const status = error.code === 'ER_DUP_ENTRY' ? 409 : 500;
    res.status(status).json({ success: false, message: 'Lỗi thêm sản phẩm', error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const {
      product_name,
      name,
      barcode,
      description,
      image_url,
      price,
      unit,
      stock,
      stockQuantity,
      min_stock,
      category_id,
      status,
    } = req.body;

    const productPrice = price == null ? null : Number(price);
    if (productPrice != null && productPrice <= 0) {
      return res.status(400).json({ success: false, message: 'Giá bán phải lớn hơn 0' });
    }
    let productBarcode = barcode || null;
    if (!productBarcode) {
      const [currentProducts] = await pool.execute(
        'SELECT barcode FROM products WHERE product_id = ?',
        [req.params.id]
      );
      productBarcode = currentProducts[0]?.barcode || null;
    }
    const importPrice = productPrice == null ? null : await getLatestImportPrice(productBarcode);
    if (productPrice != null && importPrice != null && productPrice < importPrice) {
      return res.status(400).json({ success: false, message: 'Giá bán không được nhỏ hơn giá nhập' });
    }

    await pool.execute(
      `UPDATE products
       SET product_name = COALESCE(?, product_name),
           barcode = COALESCE(?, barcode),
           description = ?,
           image_url = ?,
           price = COALESCE(?, price),
           unit = COALESCE(?, unit),
           stock = COALESCE(?, stock),
           min_stock = COALESCE(?, min_stock),
           category_id = COALESCE(?, category_id),
           status = COALESCE(?, status)
       WHERE product_id = ?`,
      [
        product_name || name || null,
        barcode || null,
        description ?? null,
        image_url ?? null,
        productPrice,
        unit || null,
        stock == null && stockQuantity == null ? null : Number(stock ?? stockQuantity),
        min_stock == null ? null : Number(min_stock),
        category_id == null ? null : Number(category_id),
        status || null,
        req.params.id,
      ]
    );

    const [rows] = await pool.execute(
      `SELECT p.*, c.category_name
       FROM products p
       JOIN categories c ON c.category_id = p.category_id
       WHERE p.product_id = ?`,
      [req.params.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy sản phẩm' });
    }
    res.json({
      success: true,
      message: 'Đã cập nhật sản phẩm',
      warning: productPrice != null && importPrice == null ? 'Sản phẩm chưa có giá nhập, không thể kiểm tra giá vốn' : null,
      data: toProduct(rows[0]),
    });
  } catch (error) {
    const status = error.code === 'ER_DUP_ENTRY' ? 409 : 500;
    res.status(status).json({ success: false, message: 'Lỗi cập nhật sản phẩm', error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.execute("UPDATE products SET status = 'deleted' WHERE product_id = ?", [req.params.id]);
    res.json({ success: true, message: 'Đã xóa sản phẩm' });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi xóa sản phẩm', error: error.message });
  }
});

module.exports = router;
