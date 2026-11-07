const crypto = require('node:crypto');
const c = require('./costing.service');
const { fail, quantity } = require('./order-billing.service');
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
async function record(pool, actor, orderId, body) {
  if (!uuid.test(body.operation_id || '') || !Array.isArray(body.items) || !body.items.length || body.items.length>1000) fail('Cần UUID và danh sách hàng hoàn hợp lệ');
  const reason=String(body.reason||'').trim(), reference=String(body.refund_reference||'').trim();
  if (!reason || reason.length>255 || !reference || reference.length>120) fail('Cần lý do và mã chứng từ hoàn tiền đã thực hiện');
  const items = body.items.map(i=>{
    if (typeof i.restock!=='boolean') fail('Phải xác nhận có nhập trả hàng hay không');
    return {id:quantity(i.order_item_id),quantity:quantity(i.quantity),restock:i.restock};
  }).sort((a,b)=>a.id-b.id);
  if(new Set(items.map(i=>i.id)).size!==items.length)fail('Trùng dòng sản phẩm');
  const hash=crypto.createHash('sha256').update(JSON.stringify({items,reason,reference})).digest('hex');
  const conn=await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [[order]]=await conn.execute('SELECT * FROM orders WHERE order_id = ? FOR UPDATE',[orderId]);
    if(!order)fail('Không tìm thấy đơn',404);
    const [[old]]=await conn.execute('SELECT * FROM sales_refunds WHERE order_id = ? AND operation_id = ? FOR UPDATE',[orderId,body.operation_id.toLowerCase()]);
    if(old) {
      if(old.request_hash!==hash)fail('UUID đã dùng cho nội dung hoàn tiền khác',409);
      await conn.commit(); return {...old,replayed:true};
    }
    if(order.reporting_version!==1 || !order.recognized_at)fail('Đơn cũ/chưa ghi nhận doanh thu cần đối soát riêng; không tự suy đoán phân bổ hoàn tiền',409);
    if(!['paid','success'].includes(order.payment_status))fail('Chỉ ghi nhận hoàn tiền cho đơn đã thanh toán',409);
    const [lines]=await conn.execute('SELECT * FROM order_items WHERE order_id = ? ORDER BY product_id FOR UPDATE',[orderId]);
    const [previous]=await conn.execute(`SELECT ri.* FROM sales_refund_items ri JOIN sales_refunds r ON r.refund_id=ri.refund_id WHERE r.order_id = ?`,[orderId]);
    const computed=[]; let refund=0n,gross=0n,cost=0n,unknown=false;
    for(const i of items) {
      const l=lines.find(l=>l.order_item_id===i.id); if(!l)fail('Dòng hàng không thuộc đơn',400);
      const before=previous.filter(p=>p.order_item_id===i.id).reduce((s,p)=>s+Number(p.quantity),0);
      if(before+i.quantity>l.quantity)fail('Số lượng hoàn vượt số đã bán còn lại',409);
      if(l.allocated_discount==null)fail('Thiếu phân bổ giảm giá của đơn',409);
      const part=v=>v==null?null:c.ratio(c.minor(v),before+i.quantity,l.quantity)-c.ratio(c.minor(v),before,l.quantity);
      const g=part(l.subtotal), d=part(l.allocated_discount), value=i.restock?part(l.cost_amount):0n;
      gross+=g; refund+=g-d;
      if(value==null)unknown=true; else cost+=value;
      computed.push({...i,productId:l.product_id,gross:g,amount:g-d,value});
    }
    // Confirmed refund is an accounting entry; this API does not send bank funds.
    const totalPreviousGross=previous.reduce((s,p)=>s+c.minor(p.gross_return),0n);
    const originalGross=c.minor(order.total_amount);
    const cumulativePoints=(points,at)=>Number(originalGross===0n?0n:(BigInt(points||0)*at)/originalGross);
    const returned=cumulativePoints(order.points_used,totalPreviousGross+gross)-cumulativePoints(order.points_used,totalPreviousGross);
    const revoked=cumulativePoints(order.points_earned,totalPreviousGross+gross)-cumulativePoints(order.points_earned,totalPreviousGross);
    const [created]=await conn.execute(`INSERT INTO sales_refunds
      (order_id,employee_id,operation_id,request_hash,amount,gross_return,cost_reversal,points_returned,points_revoked,reason,refund_reference)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)`,[orderId,actor,body.operation_id.toLowerCase(),hash,c.money(refund),c.money(gross),unknown?null:c.money(cost),returned,revoked,reason,reference]);
    for(const i of computed.sort((a,b)=>a.productId-b.productId)) {
      if(i.restock) {
        const [[p]]=await conn.execute('SELECT stock, stock_cost FROM products WHERE product_id = ? FOR UPDATE',[i.productId]);
        if(!p || Number(p.stock)+i.quantity>2147483647)fail('Không thể nhập trả hàng',409);
        await conn.execute('UPDATE products SET stock = stock + ?, stock_cost = ? WHERE product_id = ?',
          [i.quantity,c.receive(Number(p.stock),p.stock_cost,c.money(i.value)),i.productId]);
      }
      await conn.execute(`INSERT INTO sales_refund_items (refund_id,order_item_id,quantity,restock,amount,gross_return,cost_reversal) VALUES (?,?,?,?,?,?,?)`,
        [created.insertId,i.id,i.quantity,i.restock?1:0,c.money(i.amount),c.money(i.gross),c.money(i.value)]);
    }
    if(order.customer_id && (returned||revoked)) {
      await conn.execute('SELECT user_id FROM users WHERE user_id = ? FOR UPDATE',[order.customer_id]);
      // A negative balance records spent rewards that must be recovered; never silently discard the debt.
      await conn.execute('UPDATE users SET points = points + ? WHERE user_id = ?',[returned-revoked,order.customer_id]);
      for(const [type,points] of [['return_redeem',returned],['reverse_earn',-revoked]])if(points)await conn.execute(
        'INSERT INTO loyalty_transactions (user_id,order_id,points_change,type,note) VALUES (?,?,?,?,?)',
        [order.customer_id,orderId,points,type,`Hoàn hàng #${created.insertId}`]);
    }
    const allReturned=totalPreviousGross+gross===originalGross;
    await conn.execute('UPDATE orders SET refund_status = ? WHERE order_id = ?',[allReturned?'full':'partial',orderId]);
    const [[result]]=await conn.execute('SELECT * FROM sales_refunds WHERE refund_id = ?',[created.insertId]);
    await conn.commit();return {...result,replayed:false};
  } catch(e){await conn.rollback();throw e;}finally{conn.release();}
}
module.exports={record};
