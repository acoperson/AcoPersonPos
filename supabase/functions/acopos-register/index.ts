import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) return json(500, { error: "Layanan pendaftaran belum dikonfigurasi." });

    const payload = await req.json();
    const email = String(payload.email ?? "").trim().toLowerCase();
    const password = String(payload.password ?? "");
    const fullName = String(payload.full_name ?? "").trim();
    const activationCode = String(payload.activation_code ?? "").trim().toUpperCase();
    const mode = payload.registration_type === "employee" ? "employee" : "owner";
    const storeName = String(payload.store_name ?? "").trim();
    const planCode = String(payload.plan_code ?? "free").trim().toLowerCase();

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json(400, { error: "Format email tidak valid." });
    if (password.length < 8) return json(400, { error: "Password minimal 8 karakter." });
    if (fullName.length < 2 || fullName.length > 120) return json(400, { error: "Nama wajib diisi dengan benar." });
    if (activationCode.length < 8 || activationCode.length > 100) return json(400, { error: "Kode aktivasi tidak valid." });
    if (mode === "owner" && (storeName.length < 2 || storeName.length > 120)) return json(400, { error: "Nama toko minimal 2 karakter." });

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    if (mode === "owner") {
      const { data: code, error: codeError } = await admin
        .from("activation_codes")
        .select("id,plan_code,status,expires_at")
        .eq("code_hash", await sha256(activationCode))
        .maybeSingle();
      if (codeError) throw codeError;
      if (!code || code.status !== "available" || (code.expires_at && new Date(code.expires_at).getTime() <= Date.now())) {
        return json(400, { error: "Kode aktivasi tidak valid, sudah digunakan, atau kedaluwarsa." });
      }
      const { data: plan, error: planError } = await admin
        .from("subscription_plans")
        .select("code,is_active")
        .eq("code", code.plan_code)
        .maybeSingle();
      if (planError) throw planError;
      if (!plan?.is_active || plan.code !== planCode) return json(400, { error: "Kode aktivasi tidak sesuai dengan paket yang dipilih." });
    } else {
      const { data: invite, error: inviteError } = await admin
        .from("employee_invites")
        .select("id,email,status,expires_at")
        .eq("code_hash", await sha256(activationCode))
        .maybeSingle();
      if (inviteError) throw inviteError;
      if (!invite || invite.status !== "pending" || invite.email.toLowerCase() !== email ||
          (invite.expires_at && new Date(invite.expires_at).getTime() <= Date.now())) {
        return json(400, { error: "Kode anggota tidak valid, kedaluwarsa, atau bukan untuk email ini." });
      }
    }

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName,
        requested_role: mode === "owner" ? "OWNER BISNIS" : "KARYAWAN",
        registration_method: "acopos_activation_code",
      },
    });
    if (createError) {
      const message = /already|registered|exists/i.test(createError.message)
        ? "Email sudah terdaftar. Silakan masuk menggunakan email dan password."
        : createError.message;
      return json(409, { error: message });
    }
    if (!created.user) return json(500, { error: "Akun tidak berhasil dibuat." });

    return json(201, { success: true, user_id: created.user.id, message: "Akun dibuat tanpa proses konfirmasi email." });
  } catch (error) {
    console.error("acopos-register", error);
    return json(500, { error: error instanceof Error ? error.message : "Pendaftaran gagal diproses." });
  }
});
