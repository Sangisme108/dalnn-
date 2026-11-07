const assert=require('node:assert/strict');
const jwt=require('jsonwebtoken');
const secret='ai-cart-test-only';
require.cache[require.resolve('../src/config/jwt')]={loaded:true,exports:{secret}};
require.cache[require.resolve('../src/config/db')]={loaded:true,exports:{}};
const {propose,confirm}=require('../src/services/ai-cart.service');
function fixture(){
 const db={product:{product_id:1,product_name:'Táo đỏ',price:60000,stock:10,unit:'kg',status:'active'},carts:new Map(),qty:new Map(),writes:0,fail:false,lost:false};let tail=Promise.resolve();
 async function execute(sql,p=[]){
  if(sql.startsWith('SELECT user_id'))return [[{user_id:p[0]}]];
  if(sql.includes('FROM products'))return [p[0]===1&&(!sql.includes("status = 'active'")||db.product.status==='active')?[{...db.product}]:[]];
  if(sql.includes('FROM carts'))return [db.carts.has(p[0])?[{cart_id:db.carts.get(p[0])}]:[]];
  if(sql.includes('FROM cart_items')){const n=db.qty.get(p[0]+':'+p[1]);return [n==null?[]:[{quantity:n}]];}
  if(sql.startsWith('INSERT INTO carts')){db.writes++;const id=p[0]*100;db.carts.set(p[0],id);return [{insertId:id}];}
  if(sql.startsWith('INSERT INTO cart_items')){assert.match(sql,/quantity = VALUES\(quantity\)/);db.writes++;db.qty.set(p[0]+':'+p[1],p[2]);if(db.fail)throw new Error('Injected failure');return [{affectedRows:1}];}
  throw new Error('Unexpected SQL '+sql);
 }
 const pool={execute,getConnection:async()=>{let unlock,before,committed=false;return {
  beginTransaction:async()=>{const previous=tail;tail=new Promise(r=>unlock=r);await previous;before=structuredClone(db);},execute,
  commit:async()=>{committed=true;if(db.lost){db.lost=false;throw new Error('Lost commit response');}},
  rollback:async()=>{if(before&&!committed)Object.assign(db,before);},release:()=>unlock?.()
 };}};
 return {db,pool,proposal:(quantity=2,mode='add',user=3)=>propose(pool,user,{productId:1,quantity,mode}),send:(p,extra={},user=3)=>confirm(pool,user,{message:'ok',confirmationToken:p.confirmationToken,...extra})};
}
let checks=0,attempts=0,successful=0;
async function test(name,fn){await fn();checks++;console.log('PASS:',name);}
(async()=>{
 await test('proposal read-only; signed confirmation uses own customer and DB facts',async()=>{
  const f=fixture(),p=await f.proposal();assert.equal(f.db.writes,0);const r=await f.send(p,{confirmedCart:{productId:999,quantity:999,user_id:4}});
  attempts++;successful++;assert.equal(r.action.cartQuantity,2);assert.equal(f.db.qty.get('300:1'),2);assert.equal(f.db.product.stock,10);
 });
 await test('buy requests, questions and refusals never confirm',async()=>{
  for(const message of ['thêm 2 táo','không mua','ok nhưng đổi 5','100k mua được gì','đặt đơn luôn']){const f=fixture(),p=await f.proposal();await assert.rejects(f.send(p,{message}),e=>e.status===400);assert.equal(f.db.writes,0);}
 });
 await test('unsigned confirmedCart is blocked',async()=>{const f=fixture();await assert.rejects(confirm(f.pool,3,{message:'ok',confirmedCart:{productId:1,quantity:2}}),e=>e.status===400);assert.equal(f.db.writes,0);});
 await test('8 concurrent confirmations converge once',async()=>{
  const f=fixture(),p=await f.proposal(),r=await Promise.all(Array.from({length:8},()=>f.send(p)));attempts+=8;successful+=8;
  assert.equal(f.db.qty.get('300:1'),2);assert.equal(r.filter(r=>!r.action.replayed).length,1);
 });
 await test('lost commit acknowledgement replays target instead of increment',async()=>{
  const f=fixture(),p=await f.proposal();f.db.lost=true;await assert.rejects(f.send(p));const r=await f.send(p);attempts++;successful++;assert.equal(r.action.replayed,true);assert.equal(f.db.qty.get('300:1'),2);
 });
 await test('add and set preserve intended totals',async()=>{
  const f=fixture();await f.send(await f.proposal(2));await f.send(await f.proposal(3));assert.equal(f.db.qty.get('300:1'),5);await f.send(await f.proposal(1,'set'));assert.equal(f.db.qty.get('300:1'),1);attempts+=3;successful+=3;
 });
 await test('wrong account, tampering and expired tokens reject',async()=>{
  const f=fixture(),p=await f.proposal();await assert.rejects(f.send(p,{},4),e=>e.status===403);const claim=jwt.decode(p.confirmationToken);delete claim.exp;delete claim.iat;
  await assert.rejects(f.send(p,{confirmationToken:jwt.sign(claim,'wrong-key')}),e=>e.status===409);
  await assert.rejects(f.send(p,{confirmationToken:jwt.sign(claim,secret,{expiresIn:-1})}),e=>e.status===409);assert.equal(f.db.writes,0);
 });
 await test('changed price/unit/stock/status require renewed consent',async()=>{
  for(const mutate of [f=>f.db.product.price=61000,f=>f.db.product.unit='hộp',f=>f.db.product.stock=1,f=>f.db.product.status='deleted']){const f=fixture(),p=await f.proposal();mutate(f);await assert.rejects(f.send(p),e=>e.status===409);assert.equal(f.db.qty.size,0);}
 });
 await test('intervening cart changes are not overwritten',async()=>{const f=fixture(),p=await f.proposal();f.db.carts.set(3,300);f.db.qty.set('300:1',5);await assert.rejects(f.send(p),e=>e.status===409);assert.equal(f.db.qty.get('300:1'),5);});
 await test('mid-transaction error rolls back then same token can retry',async()=>{
  const f=fixture(),p=await f.proposal();f.db.fail=true;await assert.rejects(f.send(p));assert.equal(f.db.carts.size,0);assert.equal(f.db.qty.size,0);f.db.fail=false;await f.send(p);attempts++;successful++;assert.equal(f.db.qty.get('300:1'),2);
 });
 await test('invalid amounts and cart totals beyond stock reject',async()=>{
  for(const n of [0,-1,1.5,2147483648]){const f=fixture();await assert.rejects(f.proposal(n));assert.equal(f.db.writes,0);}
  const f=fixture();await f.send(await f.proposal(8));await assert.rejects(f.proposal(3),e=>e.status===409);
 });
 console.log(JSON.stringify({suite:'simulated-cart-transactions',scenarioGroups:checks,confirmedAttempts:attempts,successfulAttempts:successful,successRate:successful/attempts}));
})().catch(e=>{console.error(e);process.exitCode=1;});
