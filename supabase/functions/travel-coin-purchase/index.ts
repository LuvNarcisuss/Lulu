import { Buffer } from "node:buffer";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@3.1.0";
import { createClient } from "npm:@supabase/supabase-js@2.80.0";

// Public App Store identity confirmed by the owner on November 16, 2026.
const bundleID = "com.lulu.tourtravel";
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
    if (body.length > 32768) return json({ message: "Invalid purchase request." }, 413);
    input = JSON.parse(body);
    if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Invalid input");
  } catch { return json({ message: "Invalid purchase request." }, 400); }

  const validBundle = input.bundle_id === bundleID;
  const validEnvironment = input.environment === "Sandbox" || input.environment === "Production";
  if (!validBundle || !validEnvironment) {
    return json({ available: false, code: !validBundle ? "app_identity_mismatch" : "unsupported_environment",
      message: "This build is not configured for Apple purchases. Install the latest Lulu build." }, input.action === "status" ? 200 : 422);
  }
  const environment = input.environment === "Sandbox" ? Environment.SANDBOX : Environment.PRODUCTION;
  if (input.action === "status") return json({ available: true, environment: input.environment, bundle_id: bundleID, code: "ready" });
  if (input.action !== "deliver") return json({ message: "Invalid purchase request." }, 400);
  const signed = input.signed_transaction;
  if (typeof signed !== "string" || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(signed)) {
    return json({ message: "Invalid Apple transaction." }, 400);
  }
  try {
    // A client-selected environment never grants credit: Apple must sign the same
    // environment, bundle, product and account. Xcode transactions are not accepted.
    const verifier = new SignedDataVerifier([appleRoot], true, environment, bundleID,
      environment === Environment.PRODUCTION ? appleAppID : undefined);
    const verified = await verifier.verifyAndDecodeTransaction(signed);
    if (verified.environment !== environment || verified.bundleId !== bundleID ||
        verified.type !== "Consumable" || verified.quantity !== 1 ||
        verified.inAppOwnershipType !== "PURCHASED" || verified.revocationDate != null ||
        verified.appAccountToken?.toLowerCase() !== user.id.toLowerCase() ||
        !verified.transactionId || !/^[0-9]{1,32}$/.test(verified.transactionId) ||
        !verified.productId || !productIDs.has(verified.productId)) {
      return json({ message: "Apple transaction does not match this purchase." }, 422);
    }
    const ledger = createClient(url, serviceKey, options);
    const parameters: Record<string, string> = {
      viewer: user.id, apple_transaction: verified.transactionId, apple_product: verified.productId,
    };
    const sandbox = environment === Environment.SANDBOX;
    if (sandbox) parameters.apple_bundle = bundleID;
    const { data, error } = await ledger.rpc(sandbox ? "travel_credit_sandbox_coins" : "travel_credit_apple_coins", parameters);
    if (error || data?.committed !== true) return json({ message: "Coin delivery could not be confirmed. Check pending purchases shortly." }, 503);
    return json({ committed: true, environment: verified.environment });
  } catch {
    return json({ message: "Apple could not verify this transaction. Check pending purchases shortly." }, 422);
  }
});
