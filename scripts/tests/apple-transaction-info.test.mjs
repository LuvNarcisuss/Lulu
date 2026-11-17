import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import test from "node:test";
import {
  AppleTransactionNotFound,
  loadAppleIAPCredentials,
  lookupAppleTransaction,
} from "../../supabase/functions/travel-coin-purchase/apple-transaction-info.ts";

const bundleID = "com.lulu.tourtravel";
const transactionID = "100001";
const signedTransaction = "e30.eyJ0ZXN0Ijp0cnVlfQ.c2ln";
const fixtureIssuer = "00000000-0000-4000-8000-000000000001";
const fixtureKeyID = "ABC1234567";
const keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const encodedKey = Buffer.from(await crypto.subtle.exportKey("pkcs8", keys.privateKey)).toString("base64");
const fixtureKey = "-----BEGIN PRIVATE KEY-----\n" + encodedKey + "\n-----END PRIVATE KEY-----";

test("lookup readiness validates all credential fields and imports a P-256 private key", async () => {
  const ready = await loadAppleIAPCredentials(fixtureIssuer, fixtureKeyID, fixtureKey);
  assert.ok(ready);
  assert.equal(ready.privateKey.extractable, false);
  assert.equal(await loadAppleIAPCredentials(undefined, fixtureKeyID, fixtureKey), null);
  assert.equal(await loadAppleIAPCredentials(fixtureIssuer, "wrong", fixtureKey), null);
  assert.equal(await loadAppleIAPCredentials(fixtureIssuer, fixtureKeyID, "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----"), null);
  const otherKeys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-384" }, true, ["sign", "verify"]);
  const otherKey = Buffer.from(await crypto.subtle.exportKey("pkcs8", otherKeys.privateKey)).toString("base64");
  assert.equal(await loadAppleIAPCredentials(fixtureIssuer, fixtureKeyID, "-----BEGIN PRIVATE KEY-----\n" + otherKey + "\n-----END PRIVATE KEY-----"), null);
});

const credentials = await loadAppleIAPCredentials(fixtureIssuer, fixtureKeyID, fixtureKey);

async function assertRequest(url, request) {
  assert.equal(request.method, "GET");
  assert.equal(request.redirect, "error");
  assert.ok(request.signal instanceof AbortSignal);
  assert.equal(new URL(url).pathname, "/inApps/v1/transactions/" + transactionID);
  const authorization = new Headers(request.headers).get("Authorization");
  assert.ok(authorization.startsWith("Bearer "));
  const [header, payload, signature] = authorization.slice(7).split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url")), { alg: "ES256", kid: fixtureKeyID, typ: "JWT" });
  const claims = JSON.parse(Buffer.from(payload, "base64url"));
  assert.equal(claims.iss, fixtureIssuer);
  assert.equal(claims.aud, "appstoreconnect-v1");
  assert.equal(claims.bid, bundleID);
  assert.ok(Math.abs(Math.floor(Date.now() / 1000) - claims.iat) <= 5);
  assert.ok(claims.exp - claims.iat > 0 && claims.exp - claims.iat <= 300);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" }, keys.publicKey,
    Buffer.from(signature, "base64url"), new TextEncoder().encode(header + "." + payload),
  );
  assert.ok(valid, "Apple request JWT must carry a valid ES256 signature");
}

function responses(...fixtures) {
  const hosts = [];
  const mock = async (url, request) => {
    await assertRequest(url, request);
    hosts.push(new URL(url).origin);
    const fixture = fixtures.shift();
    assert.ok(fixture, "unexpected Apple lookup");
    return Response.json(fixture.body, { status: fixture.status });
  };
  return { hosts, lookup: environment => lookupAppleTransaction(transactionID, environment, bundleID, credentials, mock) };
}

test("Apple Get Transaction Info requests carry a signed request token and return an untrusted JWS", async () => {
  const mock = responses({ status: 200, body: { signedTransactionInfo: signedTransaction } });
  assert.deepEqual(await mock.lookup("Sandbox"), { signedTransaction, environment: "Sandbox" });
  assert.deepEqual(mock.hosts, ["https://api.storekit-sandbox.apple.com"]);
});

test("only the exact Apple transaction-not-found response permits other-environment lookup", async () => {
  const mock = responses(
    { status: 404, body: { errorCode: 4040010 } },
    { status: 200, body: { signedTransactionInfo: signedTransaction } },
  );
  assert.deepEqual(await mock.lookup("Production"), { signedTransaction, environment: "Sandbox" });
  assert.deepEqual(mock.hosts, ["https://api.storekit.apple.com", "https://api.storekit-sandbox.apple.com"]);
});

test("two Apple transaction-not-found responses terminate without further lookup", async () => {
  const miss = { status: 404, body: { errorCode: 4040010 } };
  const mock = responses(miss, miss);
  await assert.rejects(mock.lookup("Sandbox"), AppleTransactionNotFound);
  assert.deepEqual(mock.hosts, ["https://api.storekit-sandbox.apple.com", "https://api.storekit.apple.com"]);
});

test("Apple authorization, rate limit, malformed or unrelated errors cannot fall back", async () => {
  for (const fixture of [
    { status: 401, body: { errorCode: 4040010 } },
    { status: 429, body: { errorCode: 4040010 } },
    { status: 500, body: { errorCode: 4040010 } },
    { status: 404, body: { errorCode: 4040005 } },
    { status: 404, body: { errorCode: "4040010" } },
    { status: 200, body: { signedTransactionInfo: "invalid" } },
  ]) {
    const mock = responses(fixture);
    await assert.rejects(mock.lookup("Production"));
    assert.deepEqual(mock.hosts, ["https://api.storekit.apple.com"]);
  }
});
