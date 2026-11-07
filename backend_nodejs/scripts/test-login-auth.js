const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {createRequire}=require('node:module');
const bcrypt=require('bcrypt'),jwt=require('jsonwebtoken');
const src=path.resolve(__dirname,'../src'),secret='synthetic-login-tests-only';
let row,updates=0;const routes={},cache=new Map();
const pool={execute:async sql=>{if(sql.includes('FROM users u'))return [row?[row]:[]];if(sql.includes('information_schema'))return [[{count:1}]];if(sql.startsWith('UPDATE')){updates++;return [{affectedRows:1}];}throw new Error('Unexpected SQL');}};
function load(file){
 const p=path.resolve(file);if(p===path.join(src,'config/db.js'))return pool;if(p===path.join(src,'config/jwt.js'))return {secret};
 if(p===path.join(src,'services/otp.service.js'))return {};
 if(cache.has(p))return cache.get(p).exports;
 const m={exports:{}};cache.set(p,m);const req=createRequire(p);
 vm.runInNewContext(fs.readFileSync(p,'utf8'),{module:m,exports:m.exports,require:n=>n==='express'?{Router:()=>({post:(r,...h)=>routes[r]=h.at(-1),get:()=>{}})}:n.startsWith('.')?load(require.resolve(path.resolve(path.dirname(p),n))):req(n),
 process:{env:{BCRYPT_ROUNDS:'4'}},console:{warn:()=>{},error:()=>{}},Buffer,setTimeout,clearTimeout},{filename:p});return m.exports;
}
load(path.join(src,'routes/auth.routes.js'));
async function login(password){let status=200,body;await routes['/login']({body:{identifier:'fixture@test.invalid',password}},{status:n=>{status=n;return {json:b=>{body=b;}};},json:b=>{body=b;}});return {status,body};}
(async()=>{
 const hash=await bcrypt.hash('synthetic test value',4);
 row={user_id:1,email:'fixture@test.invalid',role_name:'admin',status:'active',password:hash,password_hash:hash};
 let r=await login('synthetic test value');assert.equal(r.status,200);assert.ok(typeof r.body.token==='string');assert.equal(jwt.verify(r.body.token,secret).purpose,'access');
 assert.ok(!Object.hasOwn(r.body.user,'password'));assert.ok(!Object.hasOwn(r.body.user,'password_hash'));assert.equal(updates,0);
 r=await login('synthetic invalid value');assert.equal(r.status,401);assert.ok(!r.body.token);assert.equal(updates,0);
 const authoritative=await bcrypt.hash('synthetic authoritative',4);row={...row,password:hash,password_hash:authoritative};
 r=await login('synthetic test value');assert.equal(r.status,401);r=await login('synthetic authoritative');assert.equal(r.status,200);assert.equal(updates,0);
 row=null;r=await login('synthetic test value');assert.equal(r.status,401);
 const service=load(path.join(src,'services/auth.service.js'));
 assert.equal(await service.verifyPassword('synthetic test value',hash),true);
 assert.equal(await service.verifyPassword('synthetic test value',hash.replace(/^\$2b\$/,'$2a$')),true);
 assert.equal(await service.verifyPassword('legacy synthetic','legacy synthetic'),true);
 console.log('PASS: synthetic backend login 200/401, authoritative hash precedence, bcrypt 2a/2b, legacy comparison, access JWT purpose, no hash exposure and no password writes. No real accounts or DB used.');
})().catch(()=>{console.error('FAIL: synthetic login regression; no credentials/token printed');process.exitCode=1;});
