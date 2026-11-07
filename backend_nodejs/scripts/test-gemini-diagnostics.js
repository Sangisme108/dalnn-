const assert=require('node:assert/strict');
const {safeText,safeJson,modelName,providerError,DEFAULT_GEMINI_MODEL}=require('../src/services/gemini-diagnostics');
const {planWithGemini}=require('../src/services/ai-grounding.service');
const key='AIzaFakeDiagnosticTestKeyNeverUseForAccess';
let checks=0;
async function test(name,fn){await fn();checks++;console.log('PASS:',name);}
(async()=>{
  await test('default matches verified model and models/ prefix normalizes safely',()=>{
    assert.equal(DEFAULT_GEMINI_MODEL,'gemini-3.5-flash-lite');
    assert.equal(modelName(),'gemini-3.5-flash-lite');assert.equal(modelName(' models/gemini-3.5-flash-lite '),'gemini-3.5-flash-lite');
    for(const bad of ['https://evil.invalid','../secret','model:generateContent'])assert.throws(()=>modelName(bad));
  });
  await test('HTTP404 preserves real reason but redacts credentials and project identifiers',async()=>{
    const r=await providerError({status:404,json:async()=>({error:{code:404,status:'NOT_FOUND',message:`Model no longer available to new users. key=${key}; projects/12345 project_number:98765 https://x.invalid/?access_token=other-secret`,details:[{'@type':'type.googleapis.com/google.rpc.ErrorInfo',reason:'MODEL_NOT_FOUND',metadata:{apiKey:key}}]}})}, {key,model:'gemini-2.5-flash'});
    assert.equal(r.httpStatus,404);assert.equal(r.googleStatus,'NOT_FOUND');assert.match(r.googleMessage,/no longer available to new users/);
    assert.doesNotMatch(JSON.stringify(r),new RegExp(key+'|12345|98765|other-secret'));assert.equal(r.details[0].reason,'MODEL_NOT_FOUND');
  });
  await test('quota diagnostics retain metrics and retry advice, not raw metadata',async()=>{
    const r=await providerError({status:429,json:async()=>({error:{status:'RESOURCE_EXHAUSTED',message:'Quota exceeded',details:[{'@type':'type.googleapis.com/google.rpc.QuotaFailure',violations:[{quotaMetric:'generate_content_requests',quotaId:'per_minute',description:'limit 0'}]},{'@type':'type.googleapis.com/google.rpc.RetryInfo',retryDelay:'30s'}]}})}, {key,model:'gemini-3.5-flash-lite'});
    assert.equal(r.httpStatus,429);assert.equal(r.details[0].violations[0].description,'limit 0');assert.equal(r.details[1].retryDelay,'30s');
  });
  await test('non-JSON error never logs raw response bodies',async()=>{
    const r=await providerError({status:502,json:async()=>{throw new Error(key);}}, {key,model:'test'});
    assert.equal(r.httpStatus,502);assert.doesNotMatch(JSON.stringify(r),new RegExp(key));
  });
  await test('service retains safe Google error internally while preserving fallback status contract',async()=>{
    const r=await planWithGemini({products:[],message:'Test',env:{GEMINI_API_KEY:key,GEMINI_MODEL:'models/gemini-2.5-flash'},fetcher:async(url,opts)=>{
      assert.equal(url,'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent');
      assert.equal(opts.headers['x-goog-api-key'],key);assert.equal(opts.redirect,'error');
      return {ok:false,status:404,json:async()=>({error:{status:'NOT_FOUND',message:'This model is no longer available to new users'}})};
    }});
    assert.equal(r.status,'model_unavailable');assert.equal(r.diagnostic.httpStatus,404);assert.match(r.diagnostic.googleMessage,/new users/);
    assert.doesNotMatch(JSON.stringify(r),new RegExp(key));
  });
  await test('generic redaction runs before truncation',()=>{
    const safe=safeText(`Bearer abc.def.ghi ${key} https://x.invalid/?key=opaque-secret&x=1`,key);
    assert.doesNotMatch(safe,/abc.def.ghi|opaque-secret|AIza/);
  });
  await test('all printed diagnostic strings are redacted recursively',()=>{
    const text=safeJson({model:key,nested:[{value:key}]},key);
    assert.doesNotMatch(text,new RegExp(key));assert.match(text,/REDACTED/);
  });
  console.log(`${checks} Gemini diagnostic scenario groups passed; no live requests.`);
})().catch(e=>{console.error(e);process.exitCode=1;});
