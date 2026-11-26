import { createClient } from "npm:@supabase/supabase-js@2.80.0";

const original = "https://dlbaneeshycwmhgfeokx.supabase.co";
const originalPublicKey = "sb_publishable_fILH9r1CitJSP2ZOA2HaNQ_jSZ20Znb";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });
Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ message: "Method not allowed" }, 405);
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ message: "Authentication required" }, 401);
  const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: authError } = await client.auth.getUser(authorization.substring(7));
  if (authError || !user) return json({ message: "Authentication required" }, 401);
  let parameters;
  try {
    parameters = await request.json();
  } catch {
    return json({ message: "Invalid entry request." }, 400);
  }
  if (!parameters || typeof parameters !== "object" || Array.isArray(parameters)) {
    return json({ message: "Invalid entry request." }, 400);
  }
  if ("ticket" in parameters) {
    if (!user.is_anonymous || typeof parameters.ticket !== "string" || !/^[a-f0-9]{64}$/.test(parameters.ticket)) {
      return json({ message: "A valid account transfer is required." }, 400);
    }
    try {
      const approval = await fetch(original + "/rest/v1/rpc/travel_redeem_company_ticket", {
        method: "POST", redirect: "error", signal: AbortSignal.timeout(8000),
        headers: { apikey: originalPublicKey, "Content-Type": "application/json" },
        body: JSON.stringify({ destination_id: user.id, ticket: parameters.ticket }),
      });
      if (!approval.ok) return json({ message: "Account transfer is temporarily unavailable." }, 503);
      const source = await approval.json();
      if (typeof source?.account_id !== "string") return json({ message: "Account transfer expired. Try again." }, 403);
      const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        { auth: { persistSession: false, autoRefreshToken: false } });
      const { data: link, error } = await admin.rpc("travel_bind_company_account", {
        session_user_id: user.id, imported_id: source.account_id,
      });
      if (error || link?.account_id !== source.account_id) return json({ message: "Your saved account is not ready to transfer." }, 409);
    } catch {
      return json({ message: "Account transfer is temporarily unavailable." }, 503);
    }
  }
  const { data, error } = await client.rpc("travel_bootstrap");
  if (error || !data || data.code !== 0 || typeof data.account_id !== "string" ||
      typeof data.data !== "object" || Array.isArray(data.data) || data.data === null) {
    return json({ message: "Unable to prepare your travel account. Please try again." }, 500);
  }
  return json(data);
});
