// Supabase Edge Function: qorai
// Store GEMINI_API_KEY as an Edge Function secret. Never put it in index.html.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const { message } = await req.json()
    if (!message || typeof message !== 'string') throw new Error('message required')
    const key = Deno.env.get('GEMINI_API_KEY')
    if (!key) throw new Error('GEMINI_API_KEY is not configured')
    const system = `Ты QorAI — помощник безопасного школьного общения в Казахстане.
Твоя задача: помочь учителю, родителю или ученику снизить конфликт и сформулировать уважительный ответ.
Отвечай на русском языке, если пользователь не пишет по-казахски; при казахском отвечай по-казахски.
Структура:
1. Кратко: в чём проблема и уровень конфликтности.
2. Предложи спокойный готовый ответ для отправки.
3. Если вопрос касается прав/обязанностей — дай только осторожную справочную ориентацию по законодательству Республики Казахстан и прямо укажи, что норму нужно проверить по официальному источнику Әділет перед принятием решения. Не выдумывай номера статей и цитаты.
4. Следующий безопасный шаг: разговор, консультация классного руководителя/администрации или иной пропорциональный путь.
Не определяй виновного, не угрожай, не ставь диагнозы. Не выдавай ответ за юридическую консультацию. Если есть угроза безопасности — советуй обратиться к администрации/экстренным службам по ситуации.`
    const url='https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key='+encodeURIComponent(key)
    const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({system_instruction:{parts:[{text:system}]},contents:[{role:'user',parts:[{text:message}]}],generationConfig:{temperature:0.3,maxOutputTokens:700}})})
    const j=await r.json()
    if(!r.ok) throw new Error(j?.error?.message || 'AI request failed')
    const answer=j?.candidates?.[0]?.content?.parts?.map((p:any)=>p.text||'').join('') || 'Нет ответа'
    return new Response(JSON.stringify({answer}),{headers:{...corsHeaders,'Content-Type':'application/json'}})
  } catch(e) {
    return new Response(JSON.stringify({error:String(e?.message||e)}),{status:400,headers:{...corsHeaders,'Content-Type':'application/json'}})
  }
})