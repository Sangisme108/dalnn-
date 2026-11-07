const jwt=require('jsonwebtoken');
const crypto=require('node:crypto');
const {secret}=require('../config/jwt');
const {moneyMinor}=require('./order-billing.service');
const money=n=>Number(n).toLocaleString('vi-VN')+' VNĐ';
function fail(message,status=400){throw Object.assign(new Error(message),{status});}
const positive=n=>Number.isSafeInteger(n)&&n>0&&n<=2147483647;
const fingerprint=p=>crypto.createHash('sha256').update(JSON.stringify([p.product_name,p.unit,moneyMinor(p.price)])).digest('hex');
async function propose(pool,user,body) {
  const id=Number(body.productId),count=Number(body.quantity),mode=body.mode||'set';
  if(!positive(id)||!positive(count)||!['add','set'].includes(mode))fail('Sản phẩm, số lượng hoặc cách cập nhật không hợp lệ');
  const [[p]]=await pool.execute("SELECT product_id,product_name,price,unit,stock,status FROM products WHERE product_id = ? AND status = 'active'",[id]);
  if(!p)fail('Sản phẩm không còn bán',404);
  const [[cart]]=await pool.execute('SELECT cart_id FROM carts WHERE user_id = ? ORDER BY cart_id DESC LIMIT 1',[user]);
  let before=0;
  if(cart){const [[line]]=await pool.execute('SELECT quantity FROM cart_items WHERE cart_id = ? AND product_id = ?',[cart.cart_id,id]);before=Number(line?.quantity||0);}
  const target=mode==='set'?count:before+count;
  if(!positive(target)||target>Number(p.stock))fail(`Tổng trong giỏ vượt tồn hiện tại ${p.stock} ${p.unit}`,409);
  const token=jwt.sign({purpose:'cart_confirmation',user_id:user,product_id:id,quantity:count,before,target,mode,fingerprint:fingerprint(p)},secret,{algorithm:'HS256',expiresIn:'5m'});
  return {confirmationToken:token,productId:id,quantity:count,targetQuantity:target,
    answer:`Bạn muốn ${mode==='add'?'thêm':'lấy'} ${count} ${p.unit} ${p.product_name}, giá hiện tại ${money(p.price)}/${p.unit}, tổng trong giỏ là ${target} ${p.unit}, đúng không? Chưa thêm hàng trước khi bạn xác nhận.`};
}
function confirmation(text){
  const n=String(text||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/đ/g,'d').replace(/[.!?,]/g,'').trim();
  const words=n.split(/\s+/).filter(w=>!['da','a','nha','nhe','em','anh','chi','shop','minh'].includes(w));
  return words.length>0&&words.every(w=>['ok','oke','okay','dung','roi','u','uh','dong','y','duoc','xac','nhan','vang','yes','dc','co'].includes(w));
}
async function confirm(pool,user,body) {
  if(!confirmation(body.message)||typeof body.confirmationToken!=='string'||body.confirmationToken.length>3000)fail('Cần xác nhận rõ đề nghị thêm hàng hiện tại');
  let claim;
  try {claim=jwt.verify(body.confirmationToken,secret,{algorithms:['HS256']});}catch(_){fail('Xác nhận đã hết hạn hoặc không hợp lệ. Chọn lại sản phẩm và số lượng.',409);}
  if(claim.purpose!=='cart_confirmation'||claim.user_id!==user||!positive(claim.product_id)||!positive(claim.target))fail('Xác nhận không thuộc tài khoản hiện tại',403);
  const conn=await pool.getConnection();
  try {
    await conn.beginTransaction();
    let [[cart]]=await conn.execute('SELECT cart_id FROM carts WHERE user_id = ? ORDER BY cart_id DESC LIMIT 1 FOR UPDATE',[user]);
    if(!cart){
      await conn.execute('SELECT user_id FROM users WHERE user_id = ? FOR UPDATE',[user]);
      [[cart]]=await conn.execute('SELECT cart_id FROM carts WHERE user_id = ? ORDER BY cart_id DESC LIMIT 1 FOR UPDATE',[user]);
      if(!cart){const [r]=await conn.execute('INSERT INTO carts (user_id) VALUES (?)',[user]);cart={cart_id:r.insertId};}
    }
    const [[p]]=await conn.execute('SELECT product_id,product_name,price,unit,stock,status FROM products WHERE product_id = ? FOR UPDATE',[claim.product_id]);
    const [[line]]=await conn.execute('SELECT quantity FROM cart_items WHERE cart_id = ? AND product_id = ? FOR UPDATE',[cart.cart_id,claim.product_id]);
    const current=Number(line?.quantity||0);
    if(!p)fail('Không tìm thấy sản phẩm',404);
    const replayed=current===claim.target;
    if(!replayed){
      if(current!==claim.before)fail('Giỏ đã thay đổi. Cần chọn và xác nhận lại.',409);
      if(p.status!=='active'||Number(p.stock)<claim.target)fail('Sản phẩm hết hàng hoặc tồn đã thay đổi. Cần chọn và xác nhận lại.',409);
      if(fingerprint(p)!==claim.fingerprint)fail('Giá hoặc thông tin sản phẩm đã thay đổi. Cần xác nhận lại giá mới.',409);
      await conn.execute('INSERT INTO cart_items (cart_id,product_id,quantity) VALUES (?,?,?) ON DUPLICATE KEY UPDATE quantity = VALUES(quantity)',[cart.cart_id,p.product_id,claim.target]);
    }
    await conn.commit();
    return {answer:`Giỏ hàng hiện có ${claim.target} ${p.unit} ${p.product_name}. Giá hiện tại ${money(p.price)}/${p.unit}. Chưa tạo đơn hay thanh toán.`,
      action:{type:'addToCart',productId:Number(p.product_id),quantity:claim.quantity,cartQuantity:claim.target,replayed},aiStatus:'not_needed'};
  }catch(e){await conn.rollback();throw e;}finally{conn.release();}
}
module.exports={propose,confirm,confirmation};
