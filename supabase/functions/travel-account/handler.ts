type MediaCopy = { source: string; destination: string };
type StorageEntry = { id: string | null; name: string };

export interface AccountDeletionServices {
  authenticate(token: string): Promise<string | null>;
  begin(login: string): Promise<string>;
  prepare(account: string): Promise<MediaCopy[]>;
  copy(source: string, destination: string): Promise<void>;
  publish(account: string): Promise<void>;
  list(folder: string): Promise<StorageEntry[]>;
  remove(paths: string[]): Promise<void>;
  removeIdentity(account: string): Promise<void>;
}

const response = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store" } });

export async function deleteAccount(request: Request, services: AccountDeletionServices): Promise<Response> {
  if (request.method !== "POST") return response({ error: "Method not allowed" }, 405);
  const token = /^Bearer (\S+)$/i.exec(request.headers.get("Authorization") ?? "")?.[1];
  if (!token) return response({ error: "Authentication required" }, 401);

  const body: unknown = await request.json().catch(() => null);
  if (!body || typeof body !== "object" || Object.keys(body).length !== 1 ||
      !("action" in body) || body.action !== "delete") {
    return response({ error: "Invalid deletion request" }, 400);
  }

  try {
    const login = await services.authenticate(token);
    if (!login) return response({ error: "Authentication required" }, 401);
    const account = await services.begin(login);
    for (const item of await services.prepare(account)) {
      if (!item.source.startsWith(account + "/") || !item.destination.startsWith("community/")) {
        throw Error("Invalid media retention plan");
      }
      await services.copy(item.source, item.destination);
    }
    await services.publish(account);
    await removeFolder(account, services);
    if (login !== account) await removeFolder(login, services);
    await services.removeIdentity(login);
    return response({ deleted: true });
  } catch {
    return response({ error: "Account deletion could not be completed. Please try again." }, 503);
  }
}

async function removeFolder(folder: string, services: AccountDeletionServices, depth = 0): Promise<void> {
  if (depth > 12) throw Error("Unexpected upload nesting");
  for (let batch = 0; batch < 100; batch += 1) {
    const entries = await services.list(folder);
    if (entries.length === 0) return;
    const files: string[] = [];
    for (const item of entries) {
      if (!item.name || item.name === "." || item.name === ".." || item.name.includes("/")) {
        throw Error("Invalid upload name");
      }
      const path = folder + "/" + item.name;
      if (item.id) files.push(path);
      else await removeFolder(path, services, depth + 1);
    }
    if (files.length) await services.remove(files);
  }
  throw Error("More personal uploads remain");
}
