import { createClient } from "npm:@supabase/supabase-js@2.80.0";

const headers = { "Content-Type": "application/json" };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "Method not allowed" }, 405);
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return reply({ error: "Authentication required" }, 401);
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = authorization.substring(7);
  const { data: { user }, error } = await admin.auth.getUser(token);
  if (error || !user) return reply({ error: "Authentication required" }, 401);
  let body: { action?: string };
  try { body = await request.json(); } catch { return reply({ error: "Invalid request" }, 400); }
  if (body.action !== "delete") return reply({ error: "Unsupported action" }, 400);
  // Storage objects must be removed before Auth deletes the owner; a retry uses the same identity.
  const prefix = user.id;
  const removeFolder = async (folder: string): Promise<void> => {
    const { data, error: listError } = await admin.storage.from("uploads").list(folder, { limit: 1000 });
    if (listError) throw listError;
    for (const item of data ?? []) {
      const path = `${folder}/${item.name}`;
      if (item.id) {
        const { error: removeError } = await admin.storage.from("uploads").remove([path]);
        if (removeError) throw removeError;
      } else await removeFolder(path);
    }
    if ((data?.length ?? 0) === 1000) await removeFolder(folder);
  };
  try {
    await removeFolder(prefix);
    const { error: deletionError } = await admin.auth.admin.deleteUser(user.id);
    if (deletionError) throw deletionError;
    return reply({ deleted: true });
  } catch {
    return reply({ error: "Account deletion could not be completed. Please retry." }, 500);
  }
});
