// Opt-in real Gemini evaluation against a synthetic catalog. No DB connection or writes.
const path=require('node:path');
require('dotenv').config({path:process.env.AI_SOURCE_ENV||path.resolve(__dirname,'../.env'),override:true,quiet:true});
const {answer}=require('../src/services/ai-grounding.service');
const {modelName,providerError,safeText,safeJson}=require('../src/services/gemini-diagnostics');
const {products,cases}=require('./helpers/ai-cases');
(async()=>{
  if(!process.argv.includes('--run'))throw new Error('Pass --run to call Gemini with your configured key');
  if(!process.env.GEMINI_API_KEY){console.log(safeJson({status:'not_configured',attempted:0,modelAccuracy:null,providerSuccessRate:null},process.env.GEMINI_API_KEY));return;}
  const modelArg=process.argv.indexOf('--model');
  const model=modelName(modelArg>=0?process.argv[modelArg+1]:process.env.GEMINI_MODEL);
  process.env.GEMINI_MODEL=model;
  const limitArg=process.argv.indexOf('--limit');
  const limit=limitArg>=0?Number(process.argv[limitArg+1]):12;
  if(!Number.isInteger(limit)||limit<1||limit>12)throw new Error('Evaluation limit must be 1..12');
  const pool={execute:async()=>[products]};
  const rows=[];let factual=0,semantic=0,available=0;
  const questions=cases.filter(q=>['search','compare','recommend'].includes(q.intent)).slice(0,limit);
  for(const q of questions){
    let raw=null,diagnostic=null,httpStatus=null,finishReason=null;const start=Date.now();
    const fetcher=async(...args)=>{
      const r=await fetch(...args);httpStatus=r.status;
      if(!r.ok)diagnostic=await providerError(r.clone(),{key:process.env.GEMINI_API_KEY,model});
      if(r.ok){try{const b=await r.clone().json();finishReason=b.candidates?.[0]?.finishReason||null;raw=JSON.parse(b.candidates?.[0]?.content?.parts?.map(p=>p.text||'').join(''));}catch(_){}}
      return r;
    };
    const r=await answer(pool,{message:q.question,maxPrice:q.budget},{fetcher});
    const facts=r.products.every(p=>products.some(d=>d.product_id===p.id&&d.price===p.price&&d.stock===p.stock&&d.unit===p.unit));
    const correct=r.aiStatus==='ok'&&Array.isArray(raw?.productIds)&&JSON.stringify([...new Set(raw.productIds)].sort())===JSON.stringify([...q.ids].sort());
    if(facts)factual++;if(correct)semantic++;if(r.aiStatus==='ok')available++;
    rows.push({question:q.question,status:r.aiStatus,httpStatus,finishReason,...(diagnostic?{diagnostic}:{}),latencyMs:Date.now()-start,factsCorrect:facts,modelSelectionCorrect:correct,returnedIds:r.products.map(p=>p.id)});
    if(['quota','configuration_error','model_unavailable'].includes(r.aiStatus))break;
  }
  console.log(safeJson({status:'evaluated',model:safeText(model,process.env.GEMINI_API_KEY),attempted:rows.length,
    providerSucceeded:available,providerSuccessRate:available/rows.length,
    modelSelectionAccuracy:available?semantic/available:null,
    groundedFactAccuracy:factual/rows.length,rows},process.env.GEMINI_API_KEY));
})().catch(e=>{console.error(safeJson({status:'evaluation_failed',message:safeText(e.message,process.env.GEMINI_API_KEY)},process.env.GEMINI_API_KEY));process.exitCode=1;});
