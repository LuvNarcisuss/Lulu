import { Buffer } from "node:buffer";
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@3.1.0";
import { createClient } from "npm:@supabase/supabase-js@2.80.0";

const bundleID = "com.lulu.tourtravel";
const appleRoot = Buffer.from("MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==", "base64");
const options = { auth: { persistSession: false, autoRefreshToken: false } };
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ message: "Method not allowed." }, 405);
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ message: "Authentication required." }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !publicKey) return json({ message: "Purchase verification unavailable." }, 503);
  const auth = createClient(url, publicKey, options);
  const { data: { user }, error: authError } = await auth.auth.getUser(authorization.slice(7));
  if (authError || !user) return json({ message: "Authentication required." }, 401);

  const appIDText = Deno.env.get("APPLE_APP_ID") ?? "";
  const appID = Number(appIDText);
  const ready = /^[1-9][0-9]+$/.test(appIDText) && Number.isSafeInteger(appID) && Boolean(serviceKey);

  let input: Record<string, unknown>;
  try {
    const body = await request.text();
    if (body.length > 32768) return json({ message: "Invalid purchase request." }, 413);
    input = JSON.parse(body);
    if (!input || typeof input !== "object" || Array.isArray(input)) {
      return json({ message: "Invalid purchase request." }, 400);
    }
  } catch {
    return json({ message: "Invalid purchase request." }, 400);
  }
  if (input.action === "status") return json({ available: ready });
  if (input.action !== "deliver") return json({ message: "Invalid purchase request." }, 400);
  if (!ready || !serviceKey) return json({ message: "Purchase verification unavailable." }, 503);

  const signed = input.signed_transaction;
  if (typeof signed !== "string" || !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(signed)) {
    return json({ message: "Invalid Apple transaction." }, 400);
  }
  try {
    const verifier = new SignedDataVerifier([appleRoot], true, Environment.PRODUCTION, bundleID, appID);
    const verified = await verifier.verifyAndDecodeTransaction(signed);
    if (
      verified.type !== "Consumable" || verified.quantity !== 1 ||
      verified.inAppOwnershipType !== "PURCHASED" || verified.revocationDate != null ||
      verified.appAccountToken?.toLowerCase() !== user.id.toLowerCase() ||
      !verified.transactionId || !/^[0-9]{1,32}$/.test(verified.transactionId) ||
      !verified.productId || !/^[a-z]{16}$/.test(verified.productId)
    ) {
      return json({ message: "Apple transaction does not match this purchase." }, 422);
    }

    const ledger = createClient(url, serviceKey, options);
    const { data, error } = await ledger.rpc("travel_credit_apple_coins", {
      viewer: user.id,
      apple_transaction: verified.transactionId,
      apple_product: verified.productId,
    });
    if (error || data?.committed !== true) {
      return json({ message: "Coin delivery could not be confirmed. Please retry." }, 503);
    }
    return json({ committed: true });
  } catch {
    return json({ message: "Apple could not verify this transaction. Please retry." }, 422);
  }
});
