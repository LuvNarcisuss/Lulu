import { createClient } from "npm:@supabase/supabase-js@2.80.0";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
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
  const { data, error } = await client.rpc("travel_bootstrap");
  if (error || !data || data.code !== 0 || typeof data.data !== "object" || Array.isArray(data.data) || data.data === null) {
    return json({ message: "Unable to prepare your travel account. Please try again." }, 500);
  }
  return json(data);
});
