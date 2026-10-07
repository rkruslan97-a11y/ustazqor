import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "jsr:@supabase/server@1";

interface ReqPayload { message: string }

export default {
  fetch: withSupabase({ auth: ["user"] }, async (req) => {
    try {
      const { message }: ReqPayload = await req.json();
      if (!message || typeof message !== "string") {
        return Response.json({ error: "Введите текст ситуации." }, { status: 400 });
      }

      const key = Deno.env.get("GEMINI_API_KEY");
      if (!key) {
        console.error("GEMINI_API_KEY missing");
        return Response.json({ error: "На сервере не найден GEMINI_API_KEY." }, { status: 500 });
      }

      const system = `Ты QorAI — помощник безопасного школьного общения в Казахстане.
Помогай учителю, родителю или ученику снизить конфликт и сформулировать уважительный ответ.
Если пользователь пишет по-казахски — отвечай по-казахски, иначе по-русски.
Дай: 1) краткую оценку ситуации без поиска виноватого; 2) спокойный готовый ответ; 3) если вопрос касается прав или обязанностей — только осторожную справочную ориентацию и рекомендацию проверить норму в официальной ИПС "Әділет"; не выдумывай статьи и цитаты; 4) следующий пропорциональный шаг для мирного решения.
Не ставь диагнозы, не угрожай и не выдавай ответ за юридическую консультацию.`;

      const url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key=" + encodeURIComponent(key);
      const ai = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_instruction: { parts: [{ text: system }] },
          contents: [{ role: "user", parts: [{ text: message.slice(0, 4000) }] }],
          generationConfig: { temperature: 0.3, maxOutputTokens: 700 }
        })
      });
      const raw = await ai.text();
      if (!ai.ok) {
        console.error("Gemini error", ai.status, raw);
        let msg = "Gemini API вернул ошибку " + ai.status;
        try { msg = JSON.parse(raw)?.error?.message || msg; } catch {}
        return Response.json({ error: msg }, { status: 502 });
      }
      const j = JSON.parse(raw);
      const answer = j?.candidates?.[0]?.content?.parts?.map((p: any) => p.text || "").join("") || "Gemini не вернул текст.";
      return Response.json({ answer });
    } catch (e) {
      console.error("QorAI error", e);
      return Response.json({ error: String((e as Error)?.message || e) }, { status: 500 });
    }
  }),
};