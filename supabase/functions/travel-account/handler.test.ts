import assert from "node:assert/strict";
import { test } from "node:test";
import { deleteAccount, type AccountDeletionServices } from "./handler.ts";

const user = "44444444-4444-4444-8444-444444444444";
const source = user + "/video/file.mp4";
const destination = "community/55555555-5555-4555-8555-555555555555/video.mp4";

function request(body: unknown = { action: "delete" }, token = "verified", method = "POST") {
  return new Request("https://example.invalid/travel-account", {
    method,
    headers: token ? { Authorization: "Bearer " + token } : {},
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

function fixture() {
  const events: string[] = [];
  let staged = false;
  let committed = false;
  let failCopy = false;
  let failRemoval = false;
  const services: AccountDeletionServices = {
    async authenticate(token) { return token === "verified" ? user : null; },
    async prepare(owner) {
      assert.equal(owner, user);
      events.push("prepare");
      return committed || staged ? [] : [{ source, destination }];
    },
    async copy(from, to) {
      assert.deepEqual([from, to], [source, destination]);
      events.push("copy");
      if (failCopy) throw Error("Copy failed");
      staged = true;
    },
    async publish(owner) {
      assert.equal(owner, user);
      assert.equal(staged, true);
      events.push("publish");
      committed = true;
    },
    async list(folder) {
      assert.equal(folder, user);
      events.push("list");
      return failRemoval ? [{ id: "private-file", name: "avatar.jpg" }] : [];
    },
    async remove(paths) {
      assert.deepEqual(paths, [user + "/avatar.jpg"]);
      assert.equal(committed, true);
      events.push("remove");
      throw Error("Storage unavailable");
    },
    async removeIdentity(owner) {
      assert.equal(owner, user);
      events.push("delete");
    },
  };
  return { services, events, failCopy: (value: boolean) => { failCopy = value; }, failRemoval: (value: boolean) => { failRemoval = value; } };
}

test("unauthenticated and malformed requests never mutate account data", async () => {
  const { services, events } = fixture();
  for (const [incoming, status] of [
    [request(undefined, ""), 401], [request(undefined, "invalid"), 401],
    [request(null), 400], [request({ action: "delete", user_id: "another-user" }), 400],
    [request(undefined, "verified", "GET"), 405],
  ] as const) assert.equal((await deleteAccount(incoming, services)).status, status);
  assert.deepEqual(events, []);
});

test("published media is secured before personal storage and the verified identity are removed", async () => {
  const { services, events } = fixture();
  const response = await deleteAccount(request(), services);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { deleted: true });
  assert.deepEqual(events, ["prepare", "copy", "publish", "list", "delete"]);
});

test("a copy failure leaves private storage and the identity untouched", async () => {
  const f = fixture();
  f.failCopy(true);
  assert.equal((await deleteAccount(request(), f.services)).status, 503);
  assert.deepEqual(f.events, ["prepare", "copy"]);
});

test("a storage cleanup failure can retry without copying the retained media again", async () => {
  const f = fixture();
  f.failRemoval(true);
  assert.equal((await deleteAccount(request(), f.services)).status, 503);
  assert.deepEqual(f.events, ["prepare", "copy", "publish", "list", "remove"]);
  f.failRemoval(false);
  assert.equal((await deleteAccount(request(), f.services)).status, 200);
  assert.deepEqual(f.events.slice(5), ["prepare", "publish", "list", "delete"]);
});

test("private files are removed in their own folders and the root is checked again", async () => {
  const { services, events } = fixture();
  const files = new Set([user + "/chat/photo.jpg", user + "/avatar.jpg"]);
  services.list = async (folder) => {
    if (folder === user + "/chat") {
      return files.has(folder + "/photo.jpg") ? [{ id: "photo", name: "photo.jpg" }] : [];
    }
    assert.equal(folder, user);
    return [
      ...(files.has(user + "/chat/photo.jpg") ? [{ id: null, name: "chat" }] : []),
      ...(files.has(user + "/avatar.jpg") ? [{ id: "avatar", name: "avatar.jpg" }] : []),
    ];
  };
  services.remove = async (paths) => {
    assert.equal(events.at(-1), "publish");
    for (const path of paths) assert.equal(files.delete(path), true);
  };
  assert.equal((await deleteAccount(request(), services)).status, 200);
  assert.equal(files.size, 0);
  assert.equal(events.at(-1), "delete");
});

test("a retention plan cannot copy media from another account", async () => {
  const { services, events } = fixture();
  services.prepare = async () => [{ source: "someone-else/video/file.mp4", destination }];
  assert.equal((await deleteAccount(request(), services)).status, 503);
  assert.deepEqual(events, []);
});
