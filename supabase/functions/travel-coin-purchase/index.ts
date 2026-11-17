import { Buffer } from "node:buffer";
import { createClient } from "npm:@supabase/supabase-js@2.80.0";
import { AppleVerificationUnavailable, verifyAppleTransaction } from "./apple-transaction.ts";
import { AppleReceiptRejected, verifyAppleReceipt } from "./apple-receipt.ts";
import {
  AppleTransactionNotFound,
  isAppleTransactionJWS,
  loadAppleIAPCredentials,
  lookupAppleTransaction,
} from "./apple-transaction-info.ts";

// Public App Store identity confirmed by the owner on November 16, 2026.
const productionBundleID = "com.lulu.tourtravel";
const testBundleID = "im.seex.sao2";
const appleAppID = 6832914128;
const productIDs = new Set([
  "iltpkpefqtjskxel", "eweerqrczkwsjyjn", "bfktecvbuyjzwxtp",
  "zsadvhodvgamjqqp", "qtqrufubdpyvzjzs", "ipcijraguygtcpsa",
  "azjrhiwubtjsrbzh", "qjcdfljcmzajynnd", "rzeethasxinmprew",
]);
const appleRoot = Buffer.from("MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==", "base64");
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ message: "Method not allowed." }, 405);
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ message: "Authentication required." }, 401);
  const url = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publicKey || !serviceKey) return json({ available: false, code: "service_configuration", message: "Purchases are temporarily unavailable. Please retry." }, 503);
  const auth = createClient(url, publicKey, options);
  const { data: { user }, error: authError } = await auth.auth.getUser(authorization.slice(7));
  if (authError || !user) return json({ message: "Sign in again to purchase coins." }, 401);
  let input: Record<string, unknown>;
  try {
    const body = await request.text();
    if (body.length > 1_450_000) return json({ message: "Invalid purchase request." }, 413);
    input = JSON.parse(body);
    if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Invalid input");
  } catch { return json({ message: "Invalid purchase request." }, 400); }

  const bundleID = input.bundle_id;
  const environment = input.environment;
  const testBuild = bundleID === testBundleID;
  const validBundle = bundleID === productionBundleID || (testBuild && environment === "Sandbox");
  const acceptsProduct = (id: string) => productIDs.has(id) || (testBuild && id === "neiku_30");
  const action = input.action;
  const statusRequest = action === "status" || action === "status_by_id" || action === "status_receipt";
  if (!validBundle || (environment !== "Sandbox" && environment !== "Production")) {
    return json({ available: false, code: !validBundle ? "app_identity_mismatch" : "unsupported_environment",
      message: "This build is not configured for Apple purchases. Install the latest Lulu build." }, statusRequest ? 200 : 422);
  }
  const ready = { available: true, environment, bundle_id: bundleID, code: "ready" };
  if (action === "status" || action === "status_receipt") return json(ready);
  if (action === "deliver_receipt") {
    const { transaction_id: transactionID, product_id: productID } = input;
    if (typeof transactionID !== "string" || !/^[0-9]{1,32}$/.test(transactionID) ||
        typeof productID !== "string" || !acceptsProduct(productID)) {
      return json({ message: "Invalid purchase request." }, 400);
    }
    let purchase;
    try {
      purchase = await verifyAppleReceipt(input.receipt_data, {
        bundleID, transactionID, productID, accountID: user.id, sandboxOnly: testBuild,
        appleAppID: testBuild ? undefined : appleAppID,
      });
    } catch (error) {
      const rejected = error instanceof AppleReceiptRejected;
      return json({ code: rejected ? "receipt_rejected" : "receipt_verification_unavailable",
        message: rejected ? "Apple could not verify this purchase. Check pending purchases shortly."
          : "Apple verification is temporarily unavailable. Check pending purchases shortly." }, rejected ? 422 : 503);
    }
    try {
      const ledger = createClient(url, serviceKey, options);
      const sandbox = purchase.environment === "Sandbox";
      const parameters: Record<string, string> = {
        viewer: user.id, apple_transaction: purchase.transactionID, apple_product: purchase.productID,
      };
      if (sandbox) parameters.apple_bundle = bundleID;
      const { data, error } = await ledger.rpc(sandbox ? "travel_credit_sandbox_coins" : "travel_credit_apple_coins", parameters);
      if (error || data?.committed !== true) throw new Error("Unconfirmed delivery");
      return json({ committed: true, environment: purchase.environment });
    } catch {
      return json({ code: "receipt_delivery_unavailable",
        message: "Coin delivery could not be confirmed. Check pending purchases shortly." }, 503);
    }
  }
  if (action !== "deliver" && action !== "deliver_by_id" && action !== "status_by_id") {
    return json({ message: "Invalid purchase request." }, 400);
  }

  let requestByID: { transactionID: string; productID: string } | undefined;
  let signed = input.signed_transaction;
  let settlementEnvironment = environment;
  if (action !== "deliver") {
    if (action === "deliver_by_id") {
      const { transaction_id: transactionID, product_id: productID } = input;
      if (typeof transactionID !== "string" || !/^[0-9]{1,32}$/.test(transactionID) ||
          typeof productID !== "string" || !acceptsProduct(productID)) {
        return json({ message: "Invalid purchase request." }, 400);
      }
      requestByID = { transactionID, productID };
    }
    // The test application may belong to a different App Store Connect team.
    const credentialPrefix = testBuild ? "APPLE_TEST_IAP_" : "APPLE_IAP_";
    const credentials = await loadAppleIAPCredentials(
      Deno.env.get(credentialPrefix + "ISSUER_ID"),
      Deno.env.get(credentialPrefix + "KEY_ID"),
      Deno.env.get(credentialPrefix + "PRIVATE_KEY"),
    );
    if (!credentials) {
      return json({
        ...ready, available: false, code: "apple_iap_configuration",
        message: "Apple purchases are temporarily unavailable. Please try again later.",
      }, statusRequest ? 200 : 503);
    }
    if (!requestByID) return json(ready);
    try {
      const lookup = await lookupAppleTransaction(requestByID.transactionID, environment, bundleID, credentials);
      signed = lookup.signedTransaction;
      settlementEnvironment = lookup.environment;
      if (testBuild && settlementEnvironment !== "Sandbox") {
        return json({ message: "Apple transaction does not match this purchase." }, 422);
      }
    } catch (error) {
      if (error instanceof AppleTransactionNotFound) {
        return json({ message: "Apple transaction does not match this purchase." }, 422);
      }
      console.warn("Apple transaction lookup temporarily unavailable");
      return json({ message: "Apple verification is temporarily unavailable. Check pending purchases shortly." }, 503);
    }
  }
  if (!isAppleTransactionJWS(signed)) return json({ message: "Invalid Apple transaction." }, 400);
  let verified: Record<string, unknown>;
  try {
    verified = await verifyAppleTransaction(signed, { trustedRoot: appleRoot });
  } catch (error) {
    if (error instanceof AppleVerificationUnavailable) {
      console.warn("Apple purchase verification temporarily unavailable");
      return json({ message: "Apple verification is temporarily unavailable. Check pending purchases shortly." }, 503);
    }
    console.warn("Apple purchase signature or certificate verification failed");
    return json({ message: "Apple could not verify this transaction. Check pending purchases shortly." }, 422);
  }
  // The verified JWS must match its Apple endpoint environment and the requested purchase.
  const { appAccountToken, transactionId, productId } = verified;
  if (verified.environment !== settlementEnvironment || verified.bundleId !== bundleID ||
      (!testBuild && verified.appAppleId !== undefined && verified.appAppleId !== appleAppID) ||
      verified.type !== "Consumable" || verified.quantity !== 1 ||
      verified.inAppOwnershipType !== "PURCHASED" || verified.revocationDate != null ||
      typeof appAccountToken !== "string" || appAccountToken.toLowerCase() !== user.id.toLowerCase() ||
      typeof transactionId !== "string" || !/^[0-9]{1,32}$/.test(transactionId) ||
      typeof productId !== "string" || !acceptsProduct(productId) ||
      (requestByID && (productId !== requestByID.productID ||
        (requestByID.transactionID !== transactionId && requestByID.transactionID !== verified.originalTransactionId)))) {
    console.warn("Verified Apple purchase did not match the account or catalog");
    return json({ message: "Apple transaction does not match this purchase." }, 422);
  }
  try {
    const ledger = createClient(url, serviceKey, options);
    const parameters: Record<string, string> = {
      viewer: user.id, apple_transaction: transactionId, apple_product: productId,
    };
    const sandbox = settlementEnvironment === "Sandbox";
    if (sandbox) parameters.apple_bundle = bundleID;
    const { data, error } = await ledger.rpc(sandbox ? "travel_credit_sandbox_coins" : "travel_credit_apple_coins", parameters);
    if (error || data?.committed !== true) return json({ message: "Coin delivery could not be confirmed. Check pending purchases shortly." }, 503);
    return json({ committed: true, environment: settlementEnvironment });
  } catch {
    console.warn("Verified Apple purchase could not be recorded");
    return json({ message: "Coin delivery could not be confirmed. Check pending purchases shortly." }, 503);
  }
});
