function safeText(value,key='') {
  let text=String(value||'');
  if(key)text=text.split(key).join('[REDACTED]');
  return text.replace(/AIza[\w-]+/g,'[REDACTED]')
    .replace(/(?:Bearer|Apikey)\s+[\w.\-]+/gi,'[AUTH REDACTED]')
    .replace(/projects\/[^\s/"']+/g,'projects/[REDACTED]')
    .replace(/([?&](?:key|api_key|access_token)=)[^&\s"']+/gi,'$1[REDACTED]')
    .replace(/(project(?:_number)?[=: ]+)\d+/gi,'$1[REDACTED]')
    .slice(0,1400);
}
const DEFAULT_GEMINI_MODEL='gemini-3.5-flash-lite';
function modelName(value) {
  const name=String(value||DEFAULT_GEMINI_MODEL).trim().replace(/^models\//,'');
  if(!/^[a-zA-Z0-9._-]+$/.test(name))throw new Error('Invalid Gemini model name; use the identifier returned by models.list');
  return name;
}
async function providerError(response,{key,model,apiVersion='v1beta'}={}) {
  let error={};try{error=(await response.json())?.error||{};}catch(_){/* Do not dump HTML or raw bodies. */}
  const diagnostic={httpStatus:response.status,googleStatus:safeText(error.status,key)||null,
    googleMessage:safeText(error.message,key)||'Provider returned no readable JSON error',model:safeText(model,key),apiVersion};
  if(Array.isArray(error.details))diagnostic.details=error.details.slice(0,5).map(d=>({
    type:safeText(d['@type'],key),
    ...(d.reason?{reason:safeText(d.reason,key)}:{}),
    ...(d.retryDelay?{retryDelay:safeText(d.retryDelay,key)}:{}),
    ...(Array.isArray(d.violations)?{violations:d.violations.slice(0,5).map(v=>({quotaMetric:safeText(v.quotaMetric,key),quotaId:safeText(v.quotaId,key),description:safeText(v.description,key)}))}:{}),
  }));
  return diagnostic;
}
function safeJson(value,key='') {
  return JSON.stringify(value,(_,entry)=>typeof entry==='string'?safeText(entry,key):entry,2);
}
module.exports={DEFAULT_GEMINI_MODEL,safeText,safeJson,modelName,providerError};
