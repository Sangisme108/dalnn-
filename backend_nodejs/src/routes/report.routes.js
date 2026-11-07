const express = require('express');
const pool = require('../config/db');
const reporting = require('../services/reporting.service');
const { requireAuth, requireRoles } = require('../middlewares/auth.middleware');
const router = express.Router();
router.use(requireAuth, requireRoles('admin'));
for (const endpoint of ['/revenue', '/product-performance']) router.get(endpoint, async (req,res) => {
  try {
    const data = await reporting.load(pool, req.query);
    if (endpoint === '/revenue') { const { products, ...summary } = data; res.json({success:true,data:summary}); }
    else res.json({success:true,data:data.products,quality:data.quality,filter:data.filter});
  } catch (e) { res.status(e.status||500).json({success:false,message:e.status?e.message:'Không lấy được báo cáo, vui lòng thử lại'}); }
});
module.exports = router;
