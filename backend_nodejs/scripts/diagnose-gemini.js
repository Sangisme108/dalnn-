// Explicit opt-in, safe diagnostics only. Never logs headers, keys or raw response bodies.
const path=require('node:path');
require('dotenv').config({path:process.env.AI_SOURCE_ENV||path.resolve(__dirname,'../.env'),override:true,quiet:true});
const {safeText,safeJson,modelName,providerError}=require('../src/services/gemini-diagnostics');
async function request(version,resource,body){
  const key=process.env.GEMINI_API_KEY;
  const response=await fetch(`https://generativelanguage.googleapis.com/${version}/${resource}`,{
    method:body?'POST':'GET',headers:{'x-goog-api-key':key,...(body?{'Content-Type':'application/json'}:{})},
    ...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(15000),redirect:'error',
  });
  if(!response.ok)return {ok:false,...await providerError(response,{key,model:resource.split(':')[0].split('?')[0],apiVersion:version})};
  return {ok:true,httpStatus:response.status,data:await response.json()};
}
async function main(){
  if(!process.argv.includes('--run'))throw new Error('Pass --run to authorize model discovery and one small generation probe');
  if(!process.env.GEMINI_API_KEY){console.log(safeJson({status:'not_configured'},process.env.GEMINI_API_KEY));return;}
  const arg=process.argv.indexOf('--model');
  const model=modelName(arg>=0?process.argv[arg+1]:process.env.GEMINI_MODEL);
  const models=[];let page;
  for(let i=0;i<5;i++){
    const result=await request('v1beta','models?pageSize=1000'+(page?'&pageToken='+encodeURIComponent(page):''));
    if(!result.ok){console.log(safeJson({stage:'models.list',...result},process.env.GEMINI_API_KEY));return;}
    models.push(...(result.data.models||[]));page=result.data.nextPageToken;if(!page)break;
  }
  console.log(safeJson({stage:'models.list',httpStatus:200,configuredModel:model,
    listed:models.some(m=>m.name==='models/'+model),
    note:'Model metadata does not guarantee generation entitlement or quota; a generation probe is required.',
    generateContentModels:models.filter(m=>m.supportedGenerationMethods?.includes('generateContent')&&!/image|tts|audio|robotics/.test(m.name)).map(m=>({name:m.name,methods:m.supportedGenerationMethods}))},process.env.GEMINI_API_KEY));
  for(const version of ['v1beta','v1']){
    const r=await request(version,'models/'+model);
    console.log(safeJson({stage:'models.get',apiVersion:version,model,...(r.ok?{httpStatus:r.httpStatus,methods:r.data.supportedGenerationMethods}:r)},process.env.GEMINI_API_KEY));
  }
  const r=await request('v1beta','models/'+model+':generateContent',{
    contents:[{role:'user',parts:[{text:'Reply with just OK.'}]}],generationConfig:{maxOutputTokens:64,temperature:0},
  });
  console.log(safeJson({stage:'generateContent.minimal',model,...(r.ok?{httpStatus:r.httpStatus,finishReason:r.data.candidates?.[0]?.finishReason||null,hasText:!!r.data.candidates?.[0]?.content?.parts?.some(p=>p.text)}:r)},process.env.GEMINI_API_KEY));
}
if(require.main===module)main().catch(e=>{console.error(safeJson({status:'diagnostic_failed',message:safeText(e.message,process.env.GEMINI_API_KEY)},process.env.GEMINI_API_KEY));process.exitCode=1;});
module.exports={main};
