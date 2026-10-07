import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const auth = req.headers.get("Authorization");
    if (!auth) return Response.json({ error: "Требуется вход администратора." }, { status: 401, headers: cors });

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, serviceKey);
    const token = auth.replace("Bearer ", "");
    const { data: u, error: ue } = await admin.auth.getUser(token);
    if (ue || !u.user) return Response.json({ error: "Недействительная сессия." }, { status: 401, headers: cors });

    const { data: profile } = await admin.from("profiles").select("role").eq("id", u.user.id).single();
    if (profile?.role !== "admin") return Response.json({ error: "Доступ только администрации." }, { status: 403, headers: cors });

    const body = await req.json();
    if (body.action === "create_group") {
      const name = String(body.name || "").trim();
      if (!name) throw new Error("Введите название класса.");
      const { data, error } = await admin.from("class_groups").insert({ name, created_by: u.user.id }).select("id,name").single();
      if (error) throw error;
      await admin.from("group_members").upsert({ group_id: data.id, user_id: u.user.id });
      return Response.json({ ok: true, group: data }, { headers: cors });
    }
    if (body.action === "add_member") {
      const { error } = await admin.from("group_members").upsert({ group_id: body.group_id, user_id: body.user_id });
      if (error) throw error;
      return Response.json({ ok: true }, { headers: cors });
    }
    if (body.action === "reset_password") {
      const password = String(body.password || "");
      if (!body.user_id || password.length < 6) throw new Error("Выберите пользователя и задайте пароль минимум 6 символов.");
      if (body.user_id === u.user.id) throw new Error("Свой пароль меняйте через восстановление пароля.");
      const { error } = await admin.auth.admin.updateUserById(body.user_id, { password });
      if (error) throw error;
      return Response.json({ ok: true }, { headers: cors });
    }
    return Response.json({ error: "Неизвестное действие." }, { status: 400, headers: cors });
  } catch (e) {
    console.error(e);
    return Response.json({ error: String((e as Error)?.message || e) }, { status: 400, headers: cors });
  }
});