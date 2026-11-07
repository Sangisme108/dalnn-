const express=require('express');
const pool=require('../config/db');
const {requireAuth,requireRoles}=require('../middlewares/auth.middleware');
const grounding=require('../services/ai-grounding.service');
const cart=require('../services/ai-cart.service');
const router=express.Router();
router.use(requireAuth);
const windows=new Map();
function allowAdvice(userId){
  const now=Date.now();let state=windows.get(userId);
  if(!state||state.until<=now){
    if(windows.size>=10000)for(const [id,w] of windows)if(w.until<=now)windows.delete(id);
    if(windows.size>=10000)return false;
    state={until:now+60000,count:0};windows.set(userId,state);
  }
  return ++state.count<=30;
}
function limited(req,res){if(allowAdvice(req.user.user_id))return false;res.status(429).json({success:false,message:'Bạn gửi câu hỏi quá nhanh. Hãy chờ một phút; xác nhận giỏ đã có vẫn được xử lý.'});return true;}

function failure(res,error){return res.status(error.status||503).json({success:false,message:error.status?error.message:'Chưa xác định kết quả yêu cầu. Nếu vừa xác nhận giỏ, hãy kiểm tra giỏ hoặc thử lại đúng xác nhận; không tự gửi yêu cầu mới.'});}
router.post('/cart-proposal',requireRoles('customer'),async(req,res)=>{
  try{res.json({success:true,data:await cart.propose(pool,req.user.user_id,req.body||{})});}catch(e){failure(res,e);}
});
router.post('/chat',async(req,res)=>{
  const body=req.body||{};
  try{
    if(body.confirmationToken||body.confirmedCart){
      if(req.user.role_name!=='customer')return res.status(403).json({success:false,message:'Chỉ khách hàng được xác nhận giỏ mua hàng của mình'});
      return res.json({success:true,data:await cart.confirm(pool,req.user.user_id,body)});
    }
    if(limited(req,res))return;
    res.json({success:true,data:await grounding.answer(pool,body)});
  }catch(e){failure(res,e);}
});
for(const route of ['/sales-advice','/reply','/product-introduction'])router.post(route,async(req,res)=>{
  try{
    const body=req.body||{};let productId=null;
    if(route==='/product-introduction'){
      productId=Number(body.productId);
      if(!Number.isSafeInteger(productId)||productId<=0)return res.status(400).json({success:false,message:'Mã sản phẩm không hợp lệ'});
    }
    if(limited(req,res))return;
    // toolResult/history/candidate IDs are client hints, never authoritative facts.
    res.json({success:true,data:await grounding.answer(pool,body,{productId})});
  }catch(e){failure(res,e);}
});
module.exports=router;
