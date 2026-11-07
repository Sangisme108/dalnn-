const c = require('./costing.service');
const completed = "(o.order_status IN ('completed','Hoàn thành','hoàn thành') OR o.status IN ('completed','Hoàn thành','hoàn thành'))";
const eligible = `o.payment_status IN ('paid','success') AND ${completed}
  AND COALESCE(o.status,'') NOT IN ('cancelled','canceled','rejected','refunded')
  AND COALESCE(o.order_status,'') NOT IN ('cancelled','canceled','rejected','refunded')`;
function dayNow() { return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Ho_Chi_Minh', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date()); }
function filter(query = {}) {
  const today = dayNow(); let start = null, end = null;
  const range = String(query.range || 'all');
  if (range === 'today') start = end = today;
  else if (['7days','7d','30days','30d'].includes(range)) {
    end = today; const d = new Date(today + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() - (range.startsWith('7') ? 6 : 29)); start = d.toISOString().slice(0,10);
  } else if (range === 'month') {
    const month = query.month || today.slice(0,7);
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw Object.assign(new Error('Tháng không hợp lệ'), { status: 400 });
    start = month + '-01'; end = month + '-31';
  } else if (range === 'year') {
    const year = String(query.year || today.slice(0,4));
    if (!/^\d{4}$/.test(year)) throw Object.assign(new Error('Năm không hợp lệ'), { status: 400 });
    start = year + '-01-01'; end = year + '-12-31';
  } else if (range !== 'all') throw Object.assign(new Error('Khoảng thời gian không hợp lệ'), { status: 400 });
  return { range, start, end, month: query.month || null, timezone: 'Asia/Ho_Chi_Minh' };
}
function empty() { return { gross: 0n, discount: 0n, refunds: 0n, cost: 0n, missing: 0, quantity: 0, returned: 0, orders: new Set(), voucher:0n, manual:0n, points:0n, unknownDiscount:false }; }
function add(target, e) {
  if(e.voucher==null || e.manual==null)target.unknownDiscount=true;
  else {target.voucher+=e.voucher;target.manual+=e.manual;}
  target.points+=e.points||0n;
  target.gross += e.gross; target.discount += e.discount; target.refunds += e.refund;
  if (e.cost == null) target.missing++; else target.cost += e.cost;
  target.quantity += e.quantity; target.returned += e.returned;
  if (e.order) target.orders.add(e.order);
}
function amount(n) { if (n > BigInt(Number.MAX_SAFE_INTEGER) || n < -BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('Tổng báo cáo vượt giới hạn biểu diễn'); return Number(n) / 100; }
function metrics(t) {
  const net = t.gross - t.discount - t.refunds;
  return { total_voucher_discount:t.unknownDiscount?null:amount(t.voucher),
    total_manual_discount:t.unknownDiscount?null:amount(t.manual), total_points_discount:amount(t.points),
    total_revenue: amount(t.gross), total_discount: amount(t.discount), total_refunds: amount(t.refunds),
    total_net_revenue: amount(net), total_cogs: t.missing ? null : amount(t.cost), total_profit: t.missing ? null : amount(net - t.cost),
    total_orders: t.orders.size, total_products_sold: t.quantity, total_products_returned: t.returned, net_products_sold:t.quantity-t.returned,
    missing_cost_lines: t.missing, average_order_value: t.orders.size ? amount(t.gross - t.discount) / t.orders.size : 0,
    profit_note: t.missing ? 'Chưa đủ giá vốn tại thời điểm bán/hoàn hàng; không dùng giá nhập mới nhất để suy đoán.' : null };
}
async function load(pool, query = {}) {
  const scope = filter(query); const conn = await pool.getConnection();
  let sales, returns, products, unresolved;
  try {
    await conn.query("SET time_zone = '+07:00'");
    await conn.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
    await conn.beginTransaction();
    [sales] = await conn.execute(`SELECT o.order_id, o.total_amount, o.final_amount, o.points_discount, o.voucher_discount,
      o.manual_discount, o.reporting_version, o.recognized_at,
      DATE_FORMAT(COALESCE(o.recognized_at,o.created_at),'%Y-%m-%d %H:%i:%s') AS event_at,
      oi.order_item_id, oi.product_id, oi.quantity, oi.subtotal, oi.cost_amount, oi.allocated_discount
      FROM orders o JOIN order_items oi ON oi.order_id=o.order_id WHERE ${eligible} ORDER BY o.order_id, oi.order_item_id`);
    [returns] = await conn.execute(`SELECT r.order_id, ri.*, DATE_FORMAT(r.created_at,'%Y-%m-%d %H:%i:%s') AS event_at,
      oi.product_id FROM sales_refunds r JOIN sales_refund_items ri ON ri.refund_id=r.refund_id
      JOIN order_items oi ON oi.order_item_id=ri.order_item_id`);
    [products] = await conn.execute(`SELECT p.*, c.category_name FROM products p LEFT JOIN categories c ON c.category_id=p.category_id`);
    [[unresolved]] = await conn.execute(`SELECT COUNT(*) AS count FROM orders o WHERE
      o.payment_status='refunded' OR o.status='refunded' OR o.order_status='refunded'`);
    await conn.commit();
  } catch (e) { await conn.rollback(); throw e; } finally { conn.release(); }
  const events = [], orders = new Map(); let legacy = 0, inconsistent = 0;
  for (const row of sales) { if (!orders.has(row.order_id)) orders.set(row.order_id, []); orders.get(row.order_id).push(row); }
  for (const [id, lines] of orders) {
    const o = lines[0]; const gross = c.minor(o.total_amount), net = c.minor(o.final_amount);
    if (net > gross || lines.reduce((s,l) => s+c.minor(l.subtotal),0n) !== gross) { inconsistent++; continue; }
    const shares = o.reporting_version===1 ? lines.map(l=>l.allocated_discount) : c.allocations(lines, c.money(gross-net));
    if(shares.some((v,n)=>v==null||c.minor(v)>c.minor(lines[n].subtotal))||shares.reduce((s,v)=>s+c.minor(v),0n)!==gross-net) {inconsistent++;continue;}
    if(o.reporting_version===1 && (o.voucher_discount==null||o.manual_discount==null||c.minor(o.voucher_discount)+c.minor(o.manual_discount)+c.minor(o.points_discount||'0')!==gross-net)){inconsistent++;continue;}
    if (o.recognized_at == null && inScope(o.event_at, scope)) legacy++;
    // Partition the already-snapshotted line discounts; component sums reconcile down to the cent.
    const weighted=lines.map((l,n)=>({...l,subtotal:shares[n]}));
    const voucher=o.voucher_discount==null?null:c.allocations(weighted,o.voucher_discount);
    const remaining=weighted.map((l,n)=>({...l,subtotal:c.money(c.minor(l.subtotal)-(voucher?c.minor(voucher[n]):0n))}));
    const manual=o.manual_discount==null?null:c.allocations(remaining,o.manual_discount);
    const points=shares.map((v,n)=>voucher&&manual?c.money(c.minor(v)-c.minor(voucher[n])-c.minor(manual[n])):c.allocations(weighted,o.points_discount||'0.00')[n]);
    for (let n=0;n<lines.length;n++) {
      const l = lines[n];
      events.push({ at: l.event_at, product: l.product_id, order: id, gross: c.minor(l.subtotal), discount: c.minor(shares[n]),
        voucher:voucher?c.minor(voucher[n]):null,manual:manual?c.minor(manual[n]):null,points:c.minor(points[n]), refund: 0n, cost: l.reporting_version === 1 ? c.minor(l.cost_amount) : null, quantity: Number(l.quantity), returned: 0 });
    }
  }
  for (const r of returns) events.push({ at:r.event_at, product:r.product_id, order:null, gross:0n, discount:0n,
    voucher:0n,manual:0n,points:0n,refund:c.minor(r.amount), cost:r.restock ? (r.cost_reversal == null ? null : -c.minor(r.cost_reversal)) : 0n,
    quantity:0, returned:Number(r.quantity) });
  const total = empty(), byDay=new Map(), byMonth=new Map(), byYear=new Map(), byHour=new Map(), byProduct=new Map(), lastSales=new Map();
  for (const e of events) {
    if (!inScope(e.at, scope)) continue;
    add(total,e);
    if(e.order&&(!lastSales.has(e.product)||lastSales.get(e.product)<e.at))lastSales.set(e.product,e.at);
    for (const [map,key] of [[byDay,e.at.slice(0,10)],[byMonth,e.at.slice(0,7)+'-01'],[byYear,e.at.slice(0,4)+'-01-01'],[byProduct,e.product]]) {
      if (!map.has(key)) map.set(key,empty()); add(map.get(key),e);
    }
    if(e.at.slice(0,10)===dayNow()) { const h=Number(e.at.slice(11,13)); if(!byHour.has(h))byHour.set(h,empty()); add(byHour.get(h),e); }
  }
  const buckets = map => [...map].sort(([a],[b])=>(typeof a==='number'&&typeof b==='number')?a-b:String(a).localeCompare(String(b))).map(([period,t])=>({period,...metrics(t),revenue:metrics(t).total_net_revenue,orders_count:t.orders.size}));
  const catalog=products.map(p=>{
    const t=byProduct.get(p.product_id)||empty(); const m=metrics(t);
    return { ...p, product_name:p.product_name, sale_price:Number(p.price), current_stock:Number(p.stock),
      ...m, gross_quantity_sold:t.quantity, total_quantity_sold:t.quantity-t.returned, orders_count:t.orders.size,
      average_sale_price:t.quantity ? amount(t.gross-t.discount)/t.quantity : 0,
      import_price:null, days_without_order:lastSales.has(p.product_id)?Math.floor((Date.parse(dayNow())-Date.parse(lastSales.get(p.product_id).slice(0,10)))/86400000):999,
      sell_through_rate: t.quantity+Number(p.stock)>0 ? t.quantity*100/(t.quantity+Number(p.stock)):0 };
  }).filter(p=>p.status!=='deleted'||p.total_quantity_sold>0||p.total_refunds>0)
    .sort((a,b)=>b.total_quantity_sold-a.total_quantity_sold||b.total_net_revenue-a.total_net_revenue);
  const complete = inconsistent===0 && Number(unresolved.count)===0;
  const enforce = m => complete ? m : {...m, total_profit:null,
    profit_note:'Báo cáo chưa đầy đủ: có đơn lệch tiền hoặc hoàn tiền lịch sử chưa được đối soát.'};
  const periodBuckets = map => buckets(map).map(enforce);
  return { ...enforce(metrics(total)), is_complete:complete && total.missing===0, filter:scope, products:catalog.map(enforce),
    quality:{legacy_date_orders:legacy,inconsistent_orders:inconsistent,untracked_refunded_orders:Number(unresolved.count)},
    report_note:'Ghi nhận khi hoàn thành và đã thanh toán; hoàn tiền ở kỳ phát sinh. Đơn cũ thiếu mốc ghi nhận dùng ngày tạo đơn và được đánh dấu.',
    revenue_by_time:periodBuckets(byDay), revenue_by_month:periodBuckets(byMonth), revenue_by_year:periodBuckets(byYear), revenue_by_hour_today:periodBuckets(byHour) };
}
function inScope(at, scope) { const d=at.slice(0,10); return (!scope.start||d>=scope.start)&&(!scope.end||d<=scope.end); }
module.exports={load,filter,eligible,metrics};
