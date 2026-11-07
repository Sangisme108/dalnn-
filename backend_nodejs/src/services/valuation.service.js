const costing=require('./costing.service');
const {fail}=require('./order-billing.service');
async function record(pool,actor,body) {
  const {location,item_id:id,expected_stock:stock,operation_id:key}=body;
  const reason=String(body.reason||'').trim();
  if(!['warehouse','shelf'].includes(location)||!Number.isSafeInteger(id)||id<=0||!Number.isSafeInteger(stock)||stock<0||!reason||reason.length>255||
    typeof key!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(key)) fail('Cần vị trí, mã hàng, tồn đã kiểm chứng, giá trị, lý do và UUID hợp lệ');
  const value=costing.money(costing.minor(body.stock_cost));
  if(value==null || stock===0&&value!=='0.00')fail('Giá trị tồn không hợp lệ');
  const table=location==='warehouse'?'inventory_items':'products',pk=location==='warehouse'?'inventory_item_id':'product_id';
  const conn=await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [[item]]=await conn.execute(`SELECT stock FROM ${table} WHERE ${pk} = ? FOR UPDATE`,[id]);
    const [[old]]=await conn.execute('SELECT * FROM inventory_valuations WHERE operation_id = ? FOR UPDATE',[key.toLowerCase()]);
    if(old) {
      if(old.location!==location||old.item_id!==id||old.quantity!==stock||old.stock_cost!==value||old.reason!==reason)fail('UUID đã dùng cho định giá khác',409);
      await conn.commit();return {...old,replayed:true};
    }
    if(!item||item.stock!==stock)fail('Tồn đã thay đổi, cần kiểm chứng lại trước khi định giá',409);
    const [created]=await conn.execute('INSERT INTO inventory_valuations(location,item_id,employee_id,operation_id,quantity,stock_cost,reason) VALUES (?,?,?,?,?,?,?)',[location,id,actor,key.toLowerCase(),stock,value,reason]);
    await conn.execute(`UPDATE ${table} SET stock_cost = ? WHERE ${pk} = ?`,[value,id]);
    await conn.commit();return {valuation_id:created.insertId,stock_cost:value,replayed:false};
  }catch(e){await conn.rollback();throw e;}finally{conn.release();}
}
module.exports={record};
