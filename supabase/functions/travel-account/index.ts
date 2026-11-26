import { createClient } from "npm:@supabase/supabase-js@2.80.0";
import { deleteAccount } from "./handler.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const uploads = admin.storage.from("uploads");

Deno.serve((request) => deleteAccount(request, {
  async authenticate(token) {
    const { data, error } = await admin.auth.getUser(token);
    if (error) {
      if (error.status && error.status >= 400 && error.status < 500 && error.status !== 429) return null;
      throw error;
    }
    return data.user && !data.user.is_anonymous ? data.user.id : null;
  },
  async begin(login) {
    const { data, error } = await admin.rpc("travel_begin_self_deletion", { login_id: login });
    if (error) throw error;
    if (typeof data !== "string" || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(data)) {
      throw Error("Invalid account identity");
    }
    return data;
  },
  async prepare(account) {
    const { data, error } = await admin.rpc("travel_account_media", { target_user: account, publish: false });
    if (error) throw error;
    if (!Array.isArray(data)) throw Error("Invalid media retention plan");
    return data;
  },
  async copy(source, destination) {
    const { error } = await uploads.copy(source, destination);
    if (error) throw error;
  },
  async publish(account) {
    const { error } = await admin.rpc("travel_account_media", { target_user: account, publish: true });
    if (error) throw error;
  },
  async list(folder) {
    const { data, error } = await uploads.list(folder, { limit: 100, sortBy: { column: "name", order: "asc" } });
    if (error) throw error;
    return data ?? [];
  },
  async remove(paths) {
    const { error } = await uploads.remove(paths);
    if (error) throw error;
  },
  async removeIdentity(account) {
    const { error } = await admin.auth.admin.deleteUser(account);
    if (error) throw error;
  },
}));
