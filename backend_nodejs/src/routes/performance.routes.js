const express = require('express');
const pool = require('../config/db');
const reporting = require('../services/reporting.service');
const { requireAuth, requireRoles } = require('../middlewares/auth.middleware');
const router = express.Router();
router.use(requireAuth, requireRoles('admin'));
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

router.get('/dashboard', async (req,res) => {
  try {
    const data = await reporting.load(pool, { ...req.query, range:req.query.range||'30days' });
    const products = data.products;
    const top = products.filter(p=>p.total_quantity_sold>0).slice(0,10);
    const high = products.filter(p=>p.current_stock>50).sort((a,b)=>b.current_stock-a.current_stock).slice(0,10);
    const slow = products.filter(p=>p.total_quantity_sold<5).sort((a,b)=>b.days_without_order-a.days_without_order).slice(0,10);
    res.json({success:true,data:{filter:data.filter,quality:data.quality,report_note:data.report_note,
      overview:{...data,total_revenue:data.total_net_revenue,total_stock:products.reduce((s,p)=>s+p.current_stock,0),products:undefined},
      top_products:top,top_revenue_products:[...products].filter(p=>p.total_net_revenue>0).sort((a,b)=>b.total_net_revenue-a.total_net_revenue).slice(0,10),
      high_stock_products:high,slow_products:slow,suggestions:buildSuggestions(top,high,slow),revenue_chart:data.revenue_by_time}});
  } catch(e) { res.status(e.status||500).json({success:false,message:e.status?e.message:'Không lấy được hiệu suất sản phẩm'}); }
});
module.exports=router;
