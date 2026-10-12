const express = require('express');
const fs = require('fs');
const path = require('path');
const multer = require('multer');

const router = express.Router();
const uploadDir = path.join(__dirname, '..', '..', 'uploads', 'products');

fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname || '').toLowerCase();
    cb(null, `${Date.now()}-${Math.round(Math.random() * 1e9)}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowedExts = new Set(['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif']);
    const ext = path.extname(file.originalname || '').toLowerCase();
    const isImageMime = (file.mimetype || '').startsWith('image/');
    const isImageExt = allowedExts.has(ext);

    if (!isImageMime && !isImageExt) {
      return cb(new Error('Chỉ hỗ trợ upload ảnh'));
    }
    cb(null, true);
  },
});

router.post('/product-image', (req, res) => {
  upload.single('image')(req, res, (error) => {
    if (error) {
      return res.status(400).json({
        success: false,
        message: error.message || 'Lỗi upload ảnh',
      });
    }

    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Vui lòng chọn file ảnh' });
    }

    const baseUrl = `${req.protocol}://${req.get('host')}`;
    return res.status(201).json({
      success: true,
      message: 'Upload ảnh thành công',
      data: {
        url: `${baseUrl}/uploads/products/${req.file.filename}`,
        image_url: `${baseUrl}/uploads/products/${req.file.filename}`,
      },
    });
  });
});

module.exports = router;
