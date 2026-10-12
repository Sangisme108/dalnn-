const express = require('express');
const pool = require('../config/db');

const router = express.Router();

router.get('/', async (req, res) => {
  try {
    const [rows] = await pool.execute('SELECT * FROM categories ORDER BY category_name');
    res.json({ success: true, data: rows });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lỗi lấy danh mục', error: error.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const { category_name } = req.body;
    if (!category_name) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập category_name' });
    }
    const [result] = await pool.execute(
      'INSERT INTO categories (category_name) VALUES (?)',
      [category_name.trim()]
    );
    res.status(201).json({
      success: true,
      message: 'Đã thêm danh mục',
      data: { category_id: result.insertId, category_name: category_name.trim() },
    });
  } catch (error) {
    const status = error.code === 'ER_DUP_ENTRY' ? 409 : 500;
    res.status(status).json({ success: false, message: 'Lỗi thêm danh mục', error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const { category_name } = req.body;
    if (!category_name) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập category_name' });
    }
    await pool.execute('UPDATE categories SET category_name = ? WHERE category_id = ?', [
      category_name.trim(),
      req.params.id,
    ]);
    res.json({
      success: true,
      message: 'Đã cập nhật danh mục',
      data: { category_id: Number(req.params.id), category_name: category_name.trim() },
    });
  } catch (error) {
    const status = error.code === 'ER_DUP_ENTRY' ? 409 : 500;
    res.status(status).json({ success: false, message: 'Lỗi cập nhật danh mục', error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    await pool.execute('DELETE FROM categories WHERE category_id = ?', [req.params.id]);
    res.json({ success: true, message: 'Đã xóa danh mục' });
  } catch (error) {
    const status = error.code === 'ER_ROW_IS_REFERENCED_2' ? 409 : 500;
    res.status(status).json({ success: false, message: 'Không thể xóa danh mục đang có sản phẩm', error: error.message });
  }
});

module.exports = router;
