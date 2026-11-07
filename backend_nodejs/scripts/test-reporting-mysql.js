// Explicit opt-in. Creates a uniquely named empty test DB, never copies business rows.
const assert=require('node:assert/strict');
const path=require('node:path');
const crypto=require('node:crypto');
const mysql=require('mysql2/promise');
const express=require('express');
const jwt=require('jsonwebtoken');
require('dotenv').config({path:process.env.TEST_SOURCE_ENV||path.resolve(__dirname,'../.env'),quiet:true});
const {migrate}=require('./migrate-reporting');
const costing=require('../src/services/costing.service');
const database='test_reporting_'+crypto.randomBytes(8).toString('hex');
const opts={host:process.env.DB_HOST,port:process.env.DB_PORT||4000,user:process.env.DB_USER,password:process.env.DB_PASSWORD,
  timezone:'+07:00',...(process.env.DB_SSL==='false'?{}:{ssl:{rejectUnauthorized:false}})};
let root,pool,server,base,checks=0;
async function test(name,fn){await fn();checks++;console.log('PASS:',name);}
const secret='isolated-reporting-integration-test-only';
async function api(method,url,body={},id=1){
  const response=await fetch(base+url,{method,headers:{'Content-Type':'application/json',Authorization:'Bearer '+jwt.sign({id,purpose:'access'},secret,{expiresIn:'1h'})},
    ...(['GET'].includes(method)?{}:{body:JSON.stringify(body)})});
  const data=await response.json();return {status:response.status,body:data};
}
async function sql(s,p=[]){const [r]=await pool.execute(s,p);return r;}
async function report(query=''){const r=await api('GET','/reports/revenue'+query);assert.equal(r.status,200,JSON.stringify(r.body));return r.body.data;}
async function sale(extra={},id=1){const r=await api('POST','/orders',{items:[{product_id:1,quantity:2}],payment_method:'cash',...extra},id);assert.equal(r.status,201,JSON.stringify(r.body));return Number(r.body.data.id);}
async function transaction(fn){const c=await pool.getConnection();try{await c.beginTransaction();const r=await fn(c);await c.commit();return r;}catch(e){await c.rollback();throw e;}finally{c.release();}}
const refundBody=(line,quantity=1,restock=true)=>({operation_id:crypto.randomUUID(),refund_reference:'test-'+crypto.randomUUID(),reason:'Đã hoàn tiền theo chứng từ thử nghiệm',items:[{order_item_id:line,quantity,restock}]});
(async()=>{
  if(!process.argv.includes('--run'))throw new Error('Pass --run to authorize creating/dropping an isolated test database');
  if(!/^[a-zA-Z0-9_]+$/.test(process.env.DB_NAME||''))throw new Error('Invalid source schema');
  root=await mysql.createConnection(opts);
  await root.query(`CREATE DATABASE \`${database}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`);
  for(const table of ['roles','users','categories','products','inventory_items','inventory_logs','orders','order_items','payments','loyalty_transactions','vouchers','user_vouchers','carts','cart_items','work_shifts'])
    await root.query(`CREATE TABLE \`${database}\`.\`${table}\` LIKE \`${process.env.DB_NAME}\`.\`${table}\``);
  pool=mysql.createPool({...opts,database,connectionLimit:10});
  pool.pool.on('connection',c=>c.query("SET time_zone = '+07:00'"));
  await sql("INSERT INTO roles(role_id,role_name) VALUES (1,'admin'),(2,'employee'),(3,'customer')");
  for(const id of [1,2,3])await sql("INSERT INTO users(user_id,full_name,email,password,role_id,points,status) VALUES (?,?,?,?,?,1000,'active')",[id,'Test '+id,`test${id}@invalid.local`,'not-a-login-password',id]);
  await sql("INSERT INTO categories(category_id,category_name) VALUES (1,'Test')");
  await sql("INSERT INTO products(product_id,product_name,barcode,price,unit,stock,category_id,status) VALUES (1,'A','0001',100000,'sp',0,1,'active'),(2,'B','0002',50000,'sp',10,1,'active')");
  await sql("INSERT INTO inventory_items(inventory_item_id,item_name,barcode,price,unit,stock,category_id,status) VALUES (1,'A','0001',100000,'sp',0,1,'active')");
  await test('migration is repeatable and does not backfill historical rows',async()=>{
    await sql("INSERT INTO orders(order_id,order_type,total_amount,final_amount,status,order_status,payment_status,created_at) VALUES (900,'offline',50,50,'completed','completed','paid','2020-01-01 00:00:00')");
    await sql('INSERT INTO order_items(order_id,product_id,quantity,price,subtotal) VALUES (900,2,1,50,50)');
    await migrate(pool);await migrate(pool);
    assert.equal((await sql('SELECT cost_amount FROM order_items WHERE order_id=900'))[0].cost_amount,null);
    assert.equal((await sql('SELECT reporting_version FROM orders WHERE order_id=900'))[0].reporting_version,null);
  });
  require.cache[require.resolve('../src/config/db')]={id:require.resolve('../src/config/db'),filename:require.resolve('../src/config/db'),loaded:true,exports:pool};
  require.cache[require.resolve('../src/config/jwt')]={id:require.resolve('../src/config/jwt'),filename:require.resolve('../src/config/jwt'),loaded:true,exports:{secret}};
  const app=express();app.use(express.json());
  for(const [mount,file] of [['/orders','order'],['/inventory','inventory'],['/reports','report'],['/performance','performance'],['/users','user'],['/products','product']])app.use(mount,require('../src/routes/'+file+'.routes'));
  server=app.listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));base='http://127.0.0.1:'+server.address().port;
  await test('known imports and atomic shelf transfers carry weighted cost',async()=>{
    assert.equal((await api('POST','/inventory/import',{inventory_item_id:1,quantity:20,import_price:10000})).status,200);
    assert.equal((await api('POST','/inventory/transfer-to-shelf',{inventory_item_id:1,quantity:10,operation_id:crypto.randomUUID()})).status,200);
    assert.equal((await sql('SELECT stock_cost FROM products WHERE product_id=1'))[0].stock_cost,'100000.00');
    assert.equal((await sql('SELECT stock_cost FROM inventory_items WHERE inventory_item_id=1'))[0].stock_cost,'100000.00');
  });
  let first,line;
  await test('voucher, manual and points discounts snapshot; net profit subtracts all discounts',async()=>{
    await sql("INSERT INTO vouchers(voucher_id,code,discount_type,discount_value,min_order_amount,usage_limit,status) VALUES(1,'TEST','fixed',10000,0,100,'active')");
    first=await sale({voucher_id:1,manual_discount_amount:5000,customer_id:3,points_to_use:100});
    line=(await sql('SELECT order_item_id FROM order_items WHERE order_id=?',[first]))[0].order_item_id;
    const r=await report('?range=today');
    const [[item]] = await pool.execute('SELECT * FROM order_items WHERE order_id=?',[first]);
    assert.equal(item.cost_amount,'20000.00');assert.equal(item.allocated_discount,'25000.00');
    assert.equal(r.total_revenue,200000);assert.equal(r.total_discount,25000);assert.equal(r.total_net_revenue,175000);assert.equal(r.total_cogs,20000);assert.equal(r.total_profit,155000);
    assert.equal(r.total_voucher_discount,10000);assert.equal(r.total_manual_discount,5000);assert.equal(r.total_points_discount,10000);
  });
  await test('later import price does not change a sold line or its historical profit',async()=>{
    const before=await report('?range=today');
    assert.equal((await api('POST','/inventory/import',{inventory_item_id:1,quantity:10,import_price:30000})).status,200);
    const after=await report('?range=today');assert.equal(after.total_profit,before.total_profit);
    assert.equal((await sql('SELECT cost_amount FROM order_items WHERE order_id=?',[first]))[0].cost_amount,'20000.00');
  });
  await test('multi-line paid order counted once; dashboard and product totals reconcile',async()=>{
    await sale({items:[{product_id:1,quantity:1},{product_id:2,quantity:2}]});
    const r=await report('?range=today');assert.equal(r.total_orders,2);assert.equal(r.total_revenue,400000);assert.equal(r.total_profit,null);
    const d=await api('GET','/performance/dashboard?range=today');assert.equal(d.status,200,JSON.stringify(d.body));assert.equal(d.body.data.overview.total_revenue,r.total_net_revenue);
    const p=await api('GET','/reports/product-performance?range=today');assert.equal(p.status,200);
    assert.equal(p.body.data.reduce((s,p)=>s+p.total_net_revenue,0),r.total_net_revenue);
    assert.equal((await report()).total_profit,null);assert.equal((await report()).quality.legacy_date_orders,1);
  });
  await test('unpaid and completed-but-unpaid orders do not count; cancellation restores carrying value',async()=>{
    const before=await report('?range=today');
    const stock=(await sql('SELECT stock,stock_cost FROM products WHERE product_id=1'))[0];
    const id=await sale({payment_method:'bank_transfer'});
    assert.equal((await report('?range=today')).total_orders,before.total_orders);
    const cancel=await api('PATCH','/orders/'+id+'/status',{status:'cancelled'});assert.equal(cancel.status,200,JSON.stringify(cancel.body));
    assert.deepEqual((await sql('SELECT stock,stock_cost FROM products WHERE product_id=1'))[0],stock);
    const second=await sale({payment_method:'bank_transfer'});
    assert.equal((await api('PATCH','/orders/'+second+'/status',{status:'completed'})).status,200);
    assert.equal((await report('?range=today')).total_orders,before.total_orders);
  });
  await test('partial refund reverses original net amount, cost and points, with durable concurrent deduplication',async()=>{
    const b=refundBody(line);const before=(await sql('SELECT points FROM users WHERE user_id=3'))[0].points;
    const responses=await Promise.all(Array.from({length:5},()=>api('POST','/orders/'+first+'/refunds',b)));
    for(const r of responses)assert.equal(r.status,200,JSON.stringify(r.body));
    assert.equal(responses.filter(r=>!r.body.data.replayed).length,1);
    assert.equal((await sql('SELECT COUNT(*) AS n FROM sales_refunds WHERE order_id=?',[first]))[0].n,1);
    const r=responses[0].body.data;assert.equal(Number(r.amount),87500);assert.equal(Number(r.cost_reversal),10000);assert.equal(r.points_returned,50);
    const points=(await sql('SELECT points FROM users WHERE user_id=3'))[0].points;
    assert.equal(points,before+r.points_returned-r.points_revoked);
    const old=await api('POST','/orders/'+first+'/refunds',{...b,items:[{order_item_id:line,quantity:2,restock:true}]});assert.equal(old.status,409);
    assert.equal((await api('POST','/orders/'+first+'/refunds',refundBody(line,2))).status,409);
  });
  await test('refund without restock does not reverse cost; all points are returned/revoked exactly once',async()=>{
    const r=await api('POST','/orders/'+first+'/refunds',refundBody(line,1,false));assert.equal(r.status,200,JSON.stringify(r.body));
    assert.equal(Number(r.body.data.cost_reversal),0);
    const totals=(await sql('SELECT SUM(amount) amount,SUM(points_returned) points,SUM(points_revoked) revoked FROM sales_refunds WHERE order_id=?',[first]))[0];
    assert.equal(Number(totals.amount),175000);assert.equal(Number(totals.points),100);
    assert.equal(Number(totals.revoked),(await sql('SELECT points_earned FROM orders WHERE order_id=?',[first]))[0].points_earned);
    assert.equal((await sql('SELECT refund_status FROM orders WHERE order_id=?',[first]))[0].refund_status,'full');
    assert.equal((await api('POST','/orders/'+first+'/refunds',refundBody(line))).status,409);
  });
  await test('refund event is reported in its own month; day/month/year/product rules agree',async()=>{
    // Test data only: place first sale in Jan and its refund events in Feb.
    await sql("UPDATE orders SET recognized_at='2025-01-31 23:59:59' WHERE order_id=?",[first]);
    await sql("UPDATE sales_refunds SET created_at='2025-02-01 00:00:00' WHERE order_id=?",[first]);
    const jan=await report('?range=month&month=2025-01');assert.equal(jan.total_net_revenue,175000);assert.equal(jan.total_profit,155000);
    const feb=await report('?range=month&month=2025-02');assert.equal(feb.total_net_revenue,-175000);assert.equal(feb.total_cogs,-10000);assert.equal(feb.total_profit,-165000);
    const year=await report('?range=year&year=2025');assert.equal(year.total_net_revenue,0);assert.equal(year.total_cogs,10000);assert.equal(year.total_profit,-10000);
    assert.equal(year.revenue_by_month.reduce((s,b)=>s+b.revenue,0),year.total_net_revenue);
    assert.equal(year.revenue_by_time.reduce((s,b)=>s+b.revenue,0),year.total_net_revenue);
    const p=await api('GET','/reports/product-performance?range=year&year=2025');assert.equal(p.body.data.reduce((s,p)=>s+p.total_profit,0),year.total_profit);
    assert.equal((await api('GET','/reports/revenue?range=month&month=2025-13')).status,400);
  });
  await test('transaction failure rolls back refund, stock value, points and audit event',async()=>{
    const id=await sale();const l=(await sql('SELECT order_item_id FROM order_items WHERE order_id=?',[id]))[0].order_item_id;
    const stock=(await sql('SELECT stock,stock_cost FROM products WHERE product_id=1'))[0];
    const b=refundBody(l);
    const failingPool={async getConnection(){
      const c=await pool.getConnection();return {
        beginTransaction:c.beginTransaction.bind(c),commit:c.commit.bind(c),rollback:c.rollback.bind(c),release:c.release.bind(c),
        execute:async(s,p)=>{if(s.includes('INSERT INTO sales_refund_items'))throw new Error('Injected failure');return c.execute(s,p);}
      };
    }};
    await assert.rejects(require('../src/services/refund.service').record(failingPool,1,id,b));
    assert.deepEqual((await sql('SELECT stock,stock_cost FROM products WHERE product_id=1'))[0],stock);
    assert.equal((await sql('SELECT COUNT(*) n FROM sales_refunds WHERE order_id=?',[id]))[0].n,0);
    assert.equal((await api('POST','/orders/'+id+'/refunds',b)).status,200);
  });
  await test('JWT role restrictions, expired tokens and forged actor headers remain enforced',async()=>{
    for(const id of [2,3])assert.equal((await api('POST','/orders/'+first+'/refunds',refundBody(line),id)).status,403);
    const r=await fetch(base+'/reports/revenue',{headers:{'x-user-id':'1'}});assert.equal(r.status,401);
    const expired=await fetch(base+'/reports/revenue',{headers:{Authorization:'Bearer '+jwt.sign({id:1},secret,{expiresIn:-1})}});assert.equal(expired.status,401);
  });
  await test('Owner valuation is audited, rejects stale stock, does not rewrite old sale costs',async()=>{
    const p=(await sql('SELECT stock FROM products WHERE product_id=2'))[0];
    const body={location:'shelf',item_id:2,expected_stock:p.stock,stock_cost:'160000.00',operation_id:crypto.randomUUID(),reason:'Verified opening valuation from physical count and invoices'};
    assert.equal((await api('POST','/inventory/valuation',body,2)).status,403);
    assert.equal((await api('POST','/inventory/valuation',{...body,expected_stock:p.stock+1})).status,409);
    assert.equal((await api('POST','/inventory/valuation',body)).status,200);
    assert.equal((await api('POST','/inventory/valuation',body)).body.data.replayed,true);
    assert.equal((await sql('SELECT cost_amount FROM order_items WHERE order_id=900'))[0].cost_amount,null);
    assert.equal((await report()).total_profit,null);
  });
  await test('new weighted shelf batch changes future cost only and concurrent sales conserve value',async()=>{
    const before=(await sql('SELECT stock,stock_cost FROM products WHERE product_id=1'))[0];
    assert.equal((await api('POST','/inventory/transfer-to-shelf',{inventory_item_id:1,quantity:5,operation_id:crypto.randomUUID()})).status,200);
    const after=(await sql('SELECT stock,stock_cost FROM products WHERE product_id=1'))[0];
    assert.equal(Number(after.stock_cost)-Number(before.stock_cost),100000);
    assert.equal((await sql('SELECT cost_amount FROM order_items WHERE order_id=?',[first]))[0].cost_amount,'20000.00');
    const ids=await Promise.all([sale({items:[{product_id:1,quantity:1}]}),sale({items:[{product_id:1,quantity:1}]})]);
    const issued=(await sql('SELECT SUM(cost_amount) amount FROM order_items WHERE order_id IN (?,?)',ids))[0].amount;
    const ending=(await sql('SELECT stock_cost FROM products WHERE product_id=1'))[0].stock_cost;
    assert.equal(costing.minor(after.stock_cost),costing.minor(issued)+costing.minor(ending));
  });
  await test('component allocation and line discounts reconcile to the cent',async()=>{
    await sql("INSERT INTO products(product_id,product_name,barcode,price,unit,stock,stock_cost,category_id,status) VALUES (3,'C','0003',0.03,'sp',10,0.10,1,'active'),(4,'D','0004',0.04,'sp',10,0.10,1,'active')");
    await sql("INSERT INTO vouchers(voucher_id,code,discount_type,discount_value,min_order_amount,usage_limit,status) VALUES(2,'CENT','fixed',0.01,0,100,'active')");
    await sale({items:[{product_id:3,quantity:1},{product_id:4,quantity:1}],voucher_id:2,manual_discount_amount:0.01});
    const r=await api('GET','/reports/product-performance?range=today');assert.equal(r.status,200);
    for(const p of r.body.data.filter(p=>[3,4].includes(p.product_id))) {
      assert.equal(Math.round((p.total_voucher_discount+p.total_manual_discount+p.total_points_discount)*100),Math.round(p.total_discount*100));
    }
  });
  await test('repeated payment callbacks and duplicated payment rows do not double revenue or rewards',async()=>{
    const before=await api('GET','/users/1/employee-summary');assert.equal(before.status,200,JSON.stringify(before.body));
    const points=(await sql('SELECT points FROM users WHERE user_id=3'))[0].points;
    const result=await transaction(conn=>require('../src/services/order-payment.service').markOrderPaid(conn,first,{transactionId:'duplicate-test',gateway:'bank_transfer'}));
    assert.equal(result.alreadyPaid,true);
    await sql("INSERT INTO payments(order_id,method,amount,status,paid_at) VALUES (?,'cash',175000,'paid',NOW()),(?,'cash',175000,'paid',NOW())",[first,first]);
    const after=await api('GET','/users/1/employee-summary');assert.equal(after.status,200,JSON.stringify(after.body));
    assert.equal(after.body.data.total_revenue,before.body.data.total_revenue);
    assert.equal((await sql('SELECT points FROM users WHERE user_id=3'))[0].points,points);
  });
  await test('weighted value conserves cents and preserves unknown opening cost',async()=>{
    assert.equal(costing.issue(3,'1.00',1).cost,'0.33');assert.equal(costing.issue(2,'0.67',1).cost,'0.34');
    assert.equal(costing.receive(10,null,'100.00'),null);assert.equal(costing.receive(0,null,'100.00'),'100.00');
    assert.equal(costing.issue(10,null,10).remaining,'0.00');
  });
})().catch(e=>{console.error(e.stack);process.exitCode=1;}).finally(async()=>{
  if(server)await new Promise(resolve=>server.close(resolve));if(pool)await pool.end();
  if(root){await root.query(`DROP DATABASE IF EXISTS \`${database}\``);await root.end();}
  console.log(`${checks} MySQL reporting scenario groups passed; isolated database cleaned up.`);
});
