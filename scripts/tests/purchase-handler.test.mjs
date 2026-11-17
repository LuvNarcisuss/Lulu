import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import vm from "node:vm";
import test from "node:test";
import assert from "node:assert/strict";
import { verifyAppleReceipt, AppleReceiptRejected } from "../../supabase/functions/travel-coin-purchase/apple-receipt.ts";

const root = new URL("../../", import.meta.url);
const source = readFileSync(new URL("supabase/functions/travel-coin-purchase/index.ts", root), "utf8");
const app = "com.lulu.tourtravel";
const account = "00000000-0000-4000-8000-000000000001";
const products = [
  "iltpkpefqtjskxel", "eweerqrczkwsjyjn", "bfktecvbuyjzwxtp",
  "zsadvhodvgamjqqp", "qtqrufubdpyvzjzs", "ipcijraguygtcpsa",
  "azjrhiwubtjsrbzh", "qjcdfljcmzajynnd", "rzeethasxinmprew",
];
const delivery = {
  action: "deliver", signed_transaction: "e30.eyJ0ZXN0Ijp0cnVlfQ.c2ln", bundle_id: app, environment: "Sandbox",
};
const statusByID = { action: "status_by_id", bundle_id: app, environment: "Sandbox" };
const deliveryByID = {
  ...statusByID, action: "deliver_by_id", transaction_id: "100001", product_id: products[0],
};

class AppleVerificationUnavailable extends Error {}
class AppleTransactionNotFound extends Error {}

function harness({
  transaction = {}, verificationError, ledgerError, throwsOnLedger = false, authenticated = true,
  lookupReady = false, lookupEnvironment = "Sandbox", lookupError, receiptReply, receiptNetworkError,
} = {}) {
  const calls = [];
  const lookups = [];
  const credentialChecks = [];
  const receiptChecks = [];
  let handler;
  const payload = {
    environment: "Sandbox",
    bundleId: app,
    productId: products[0],
    appAccountToken: account,
    transactionId: "100001",
    quantity: 1,
    type: "Consumable",
    inAppOwnershipType: "PURCHASED",
    ...transaction,
  };
  const client = {
    auth: { getUser: async () => ({ data: { user: authenticated ? { id: account } : null }, error: null }) },
    rpc: async (name, args) => {
      calls.push({ name, args });
      if (throwsOnLedger) throw new Error("Unavailable");
      return { data: { committed: !ledgerError }, error: ledgerError };
    },
  };
  const env = {
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_ANON_KEY: "test-public",
    SUPABASE_SERVICE_ROLE_KEY: "test-service",
    APPLE_IAP_ISSUER_ID: "fixture-issuer",
    APPLE_IAP_KEY_ID: "fixture-key-id",
    APPLE_IAP_PRIVATE_KEY: "fixture-signing-key",
    APPLE_TEST_IAP_ISSUER_ID: "test-app-issuer",
    APPLE_TEST_IAP_KEY_ID: "test-app-key-id",
    APPLE_TEST_IAP_PRIVATE_KEY: "test-app-signing-key",
  };
  const js = stripTypeScriptTypes(source.replace(/^import\s[\s\S]+?;\n/gm, ""));
  vm.runInNewContext(js, {
    Buffer, Response, Request, JSON, Number, Boolean, Error,
    console: { warn() {} },
    AppleVerificationUnavailable,
    AppleTransactionNotFound,
    AppleReceiptRejected,
    verifyAppleReceipt: (encoded, expectation) => verifyAppleReceipt(encoded, expectation, async (url, init) => {
      receiptChecks.push({ url, body: JSON.parse(init.body) });
      if (receiptNetworkError) throw receiptNetworkError;
      const reply = url.includes('buy.itunes.apple.com') && receiptReply?.environment !== 'Production'
        ? { status: 21007 } : receiptReply;
      return new Response(JSON.stringify(reply), { status: 200 });
    }),
    loadAppleIAPCredentials: async (issuerID, keyID, privateKey) => {
      credentialChecks.push([issuerID, keyID, privateKey]);
      return lookupReady ? { issuerID, keyID, privateKey } : null;
    },
    lookupAppleTransaction: async (transactionID, environment, bundle, credentials) => {
      lookups.push({ transactionID, environment, bundle, credentials });
      if (lookupError) throw lookupError;
      return { environment: lookupEnvironment, signedTransaction: delivery.signed_transaction };
    },
    isAppleTransactionJWS: value => typeof value === "string" && /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value),
    verifyAppleTransaction: async (signed, options) => {
      assert.equal(signed, delivery.signed_transaction);
      assert.ok(options.trustedRoot.length > 0);
      if (verificationError) throw verificationError;
      return payload;
    },
    createClient: () => client,
    Deno: { env: { get: key => env[key] }, serve: fn => handler = fn },
  });
  return {
    calls,
    lookups,
    credentialChecks,
    receiptChecks,
    request: async input => {
      const response = await handler(new Request("https://example.test", {
        method: "POST", headers: { Authorization: "Bearer test-user" }, body: JSON.stringify(input),
      }));
      return { status: response.status, body: await response.json() };
    },
  };
}

test("sandbox readiness does not require an App Store Connect key", async () => {
  const { body } = await harness().request({ action: "status", bundle_id: app, environment: "Sandbox" });
  assert.equal(body.available, true);
});

test("unknown bundle is rejected before offering checkout", async () => {
  const { body } = await harness().request({ action: "status", bundle_id: "com.other.app", environment: "Sandbox" });
  assert.equal(body.available, false);
});

test("authorized test bundle uses its own credentials and sandbox ledger", async () => {
  const audit = harness({ lookupReady: true, transaction: { bundleId: "im.seex.sao2" } });
  const result = await audit.request({ ...deliveryByID, bundle_id: "im.seex.sao2" });
  assert.equal(result.status, 200);
  assert.equal(result.body.committed, true);
  assert.equal(audit.lookups[0].bundle, "im.seex.sao2");
  assert.deepEqual(audit.credentialChecks, [["test-app-issuer", "test-app-key-id", "test-app-signing-key"]]);
  assert.equal(audit.calls[0].name, "travel_credit_sandbox_coins");
  assert.equal(audit.calls[0].args.apple_bundle, "im.seex.sao2");
});

test("test bundle cannot request production checkout or credit", async () => {
  const audit = harness({ lookupReady: true, transaction: { bundleId: "im.seex.sao2", environment: "Production" } });
  for (const action of ["status", "status_by_id", "deliver", "deliver_by_id"]) {
    const result = await audit.request({ ...deliveryByID, action, bundle_id: "im.seex.sao2", environment: "Production" });
    assert.notEqual(result.body.available, true);
    assert.notEqual(result.body.committed, true);
  }
  assert.equal(audit.lookups.length, 0);
  assert.equal(audit.calls.length, 0);
});

test("Apple production fallback cannot credit a sandbox-only test bundle", async () => {
  const audit = harness({ lookupReady: true, lookupEnvironment: "Production", transaction: {
    bundleId: "im.seex.sao2", environment: "Production",
  } });
  assert.equal((await audit.request({ ...deliveryByID, bundle_id: "im.seex.sao2" })).status, 422);
  assert.equal(audit.calls.length, 0);
});

test("verified transactions cannot cross the formal and test bundle boundary", async () => {
  for (const [requested, signed] of [["im.seex.sao2", app], [app, "im.seex.sao2"]]) {
    const audit = harness({ lookupReady: true, transaction: { bundleId: signed } });
    assert.equal((await audit.request({ ...deliveryByID, bundle_id: requested })).status, 422);
    assert.equal(audit.calls.length, 0);
  }
});

for (const product of products) {
  test(`verified sandbox ${product} uses only sandbox ledger`, async () => {
    const audit = harness({ transaction: { productId: product } });
    const result = await audit.request(delivery);
    assert.deepEqual(result, { status: 200, body: { committed: true, environment: "Sandbox" } });
    assert.equal(audit.calls.length, 1);
    assert.equal(audit.calls[0].name, "travel_credit_sandbox_coins");
    assert.equal(audit.calls[0].args.apple_product, product);
    assert.equal(audit.calls[0].args.apple_bundle, app);
  });
}

test("production uses production ledger", async () => {
  const audit = harness({ transaction: { environment: "Production", appAppleId: 6832914128 } });
  const result = await audit.request({ ...delivery, environment: "Production" });
  assert.deepEqual(result, { status: 200, body: { committed: true, environment: "Production" } });
  assert.equal(audit.calls[0].name, "travel_credit_apple_coins");
});

for (const transaction of [
  { appAccountToken: "00000000-0000-4000-8000-000000000002" },
  { appAccountToken: null },
  { bundleId: "com.other.app" },
  { appAppleId: 1 },
  { environment: "Xcode" },
  { environment: "Production" },
  { productId: "unknownproductxx" },
  { quantity: 2 },
  { type: "Non-Consumable" },
  { inAppOwnershipType: "FAMILY_SHARED" },
  { revocationDate: 1 },
  { transactionId: "not-a-transaction" },
]) {
  test(`invalid verified purchase cannot credit ${JSON.stringify(transaction)}`, async () => {
    const audit = harness({ transaction });
    assert.equal((await audit.request(delivery)).status, 422);
    assert.equal(audit.calls.length, 0);
  });
}

test("rejected signatures never reach the ledger", async () => {
  const audit = harness({ verificationError: new Error("Invalid signature") });
  assert.equal((await audit.request(delivery)).status, 422);
  assert.equal(audit.calls.length, 0);
});

test("unavailable Apple certificate status is retryable without credit", async () => {
  const audit = harness({ verificationError: new AppleVerificationUnavailable() });
  assert.equal((await audit.request(delivery)).status, 503);
  assert.equal(audit.calls.length, 0);
});

test("failed persistence cannot report success", async () => {
  for (const options of [{ ledgerError: { message: "Unavailable" } }, { throwsOnLedger: true }]) {
    const audit = harness(options);
    const result = await audit.request(delivery);
    assert.equal(result.status, 503);
    assert.notEqual(result.body.committed, true);
  }
});

test("transaction-ID readiness checks credentials without contacting Apple and preserves legacy readiness", async () => {
  const missing = harness();
  const ready = harness({ lookupReady: true });
  assert.equal((await missing.request(statusByID)).body.available, false);
  assert.equal((await missing.request({ ...statusByID, action: "status" })).body.available, true);
  assert.deepEqual(await ready.request(statusByID), {
    status: 200,
    body: { available: true, environment: "Sandbox", bundle_id: app, code: "ready" },
  });
  assert.deepEqual(ready.credentialChecks, [["fixture-issuer", "fixture-key-id", "fixture-signing-key"]]);
  assert.equal(ready.lookups.length, 0);
});

test("unauthorized or foreign-bundle callers cannot use the lookup credentials", async () => {
  const unauthorized = harness({ authenticated: false, lookupReady: true });
  assert.equal((await unauthorized.request(deliveryByID)).status, 401);
  assert.equal(unauthorized.credentialChecks.length, 0);
  const foreign = harness({ lookupReady: true });
  assert.equal((await foreign.request({ ...statusByID, bundle_id: "com.other.app" })).body.available, false);
  assert.equal(foreign.credentialChecks.length, 0);
});

test("delivery by ID credits the verified lookup environment and canonical transaction ID", async () => {
  const audit = harness({ lookupReady: true, transaction: { originalTransactionId: "100000" } });
  const result = await audit.request({
    ...deliveryByID, environment: "Production", transaction_id: "100000", signed_transaction: "invalid",
  });
  assert.deepEqual(result, { status: 200, body: { committed: true, environment: "Sandbox" } });
  assert.equal(audit.lookups.length, 1);
  assert.equal(audit.lookups[0].environment, "Production");
  assert.equal(audit.lookups[0].transactionID, "100000");
  assert.equal(audit.calls.length, 1);
  assert.equal(audit.calls[0].name, "travel_credit_sandbox_coins");
  assert.equal(audit.calls[0].args.apple_transaction, "100001");
});

test("delivery by ID with a verified production transaction uses the production ledger", async () => {
  const audit = harness({ lookupReady: true, lookupEnvironment: "Production", transaction: { environment: "Production" } });
  const result = await audit.request(deliveryByID);
  assert.deepEqual(result, { status: 200, body: { committed: true, environment: "Production" } });
  assert.equal(audit.calls[0].name, "travel_credit_apple_coins");
});

test("malformed transaction IDs and unknown products fail before any Apple lookup", async () => {
  const audit = harness({ lookupReady: true });
  const badID = await audit.request({ ...deliveryByID, transaction_id: "../production" });
  const noProduct = await audit.request({ ...deliveryByID, product_id: "com.other.app" });
  assert.equal(badID.status, 400);
  assert.equal(noProduct.status, 400);
  assert.equal(audit.lookups.length, 0);
  assert.equal(audit.calls.length, 0);
});

test("credentials, Apple not found, and transport failures cannot grant credit", async () => {
  for (const [options, status] of [
    [{}, 503],
    [{ lookupReady: true, lookupError: new AppleTransactionNotFound() }, 422],
    [{ lookupReady: true, lookupError: new Error("Transport unavailable") }, 503],
  ]) {
    const audit = harness(options);
    assert.equal((await audit.request(deliveryByID)).status, status);
    assert.equal(audit.calls.length, 0);
  }
});

test("lookup requires a verified transaction with matching environment, ID, product and owner", async () => {
  for (const options of [
    { verificationError: new Error("Invalid Apple signature") },
    { transaction: { environment: "Production" } },
    { transaction: { transactionId: "100002", originalTransactionId: "100003" } },
    { transaction: { productId: products[1] } },
    { transaction: { appAccountToken: "00000000-0000-4000-8000-000000000002" } },
    { transaction: { quantity: 2 } },
    { transaction: { revocationDate: 1 } },
  ]) {
    const audit = harness({ lookupReady: true, ...options });
    assert.equal((await audit.request(deliveryByID)).status, 422);
    assert.equal(audit.lookups.length, 1);
    assert.equal(audit.calls.length, 0);
  }
});


test("owner-selected test product credits 400-tier sandbox delivery only", async () => {
  const h = harness({ lookupReady: true, transaction: { bundleId: "im.seex.sao2", productId: "neiku_30" } });
  const result = await h.request({ ...deliveryByID, bundle_id: "im.seex.sao2", product_id: "neiku_30" });
  assert.equal(result.status, 200);
  assert.equal(h.calls[0].args.apple_product, "neiku_30");
  assert.equal(h.calls[0].args.apple_bundle, "im.seex.sao2");
  const formal = harness({ lookupReady: true, transaction: { productId: "neiku_30" } });
  assert.equal((await formal.request({ ...deliveryByID, product_id: "neiku_30" })).status, 400);
  assert.equal(formal.calls.length, 0);
});


test("StoreKit 1 receipt checkout does not require API signing credentials", async () => {
  const audit = harness();
  const result = await audit.request({ action: "status_receipt", bundle_id: "im.seex.sao2", environment: "Sandbox" });
  assert.equal(result.status, 200);
  assert.equal(result.body.available, true);
  assert.equal(audit.credentialChecks.length, 0);
});


const receiptInput = { action: "deliver_receipt", bundle_id: "im.seex.sao2", environment: "Sandbox",
  transaction_id: "100001", product_id: "neiku_30", receipt_data: Buffer.from("receipt fixture").toString("base64") };
function receiptReply(row = {}) {
  return { status: 0, environment: "Sandbox", receipt: { bundle_id: "im.seex.sao2", receipt_type: "ProductionSandbox",
    in_app: [{ transaction_id: "100001", product_id: "neiku_30", quantity: "1", purchase_date_ms: "1794800000000", ...row }] } };
}

test("real receipt verifier feeds only the requested sandbox purchase into the existing atomic ledger", async () => {
  const audit = harness({ receiptReply: receiptReply() });
  assert.deepEqual(await audit.request(receiptInput), { status: 200, body: { committed: true, environment: "Sandbox" } });
  assert.equal(audit.credentialChecks.length, 0);
  assert.equal(audit.lookups.length, 0);
  assert.equal(audit.receiptChecks.length, 2);
  assert.equal(audit.calls.length, 1);
  assert.equal(audit.calls[0].name, "travel_credit_sandbox_coins");
  assert.deepEqual({ ...audit.calls[0].args }, { viewer: account, apple_transaction: "100001", apple_product: "neiku_30", apple_bundle: "im.seex.sao2" });
});

for (const row of [{ product_id: "other" }, { transaction_id: "200002" }, { quantity: "2" },
  { app_account_token: "00000000-0000-4000-8000-000000000002" }, { cancellation_date_ms: "1794800001000" }]) {
  test(`receipt rejection cannot write coins: ${JSON.stringify(row)}`, async () => {
    const audit = harness({ receiptReply: receiptReply(row) });
    assert.equal((await audit.request(receiptInput)).status, 422);
    assert.equal(audit.calls.length, 0);
  });
}

test("missing receipt cannot use a client claimed purchase as proof", async () => {
  const audit = harness({ receiptReply: receiptReply() });
  assert.equal((await audit.request({ ...receiptInput, receipt_data: undefined })).status, 422);
  assert.equal(audit.calls.length, 0);
  assert.equal(audit.receiptChecks.length, 0);
});

test("receipt transport and ledger outages do not acknowledge delivery", async () => {
  for (const options of [{ receiptNetworkError: new Error("offline") }, { ledgerError: true }, { throwsOnLedger: true }]) {
    const audit = harness({ receiptReply: receiptReply(), ...options });
    const result = await audit.request(receiptInput);
    assert.equal(result.status, 503);
    assert.notEqual(result.body.committed, true);
  }
});

test("receipt path denies authentication failure and unapproved app identities", async () => {
  const unsigned = harness({ authenticated: false });
  assert.equal((await unsigned.request(receiptInput)).status, 401);
  for (const values of [{ bundle_id: "other.app" }, { environment: "Production" }]) {
    const audit = harness({ receiptReply: receiptReply() });
    assert.equal((await audit.request({ ...receiptInput, ...values })).status, 422);
    assert.equal(audit.calls.length, 0);
  }
});
