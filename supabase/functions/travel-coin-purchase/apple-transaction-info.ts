import { Buffer } from "node:buffer";

export type ApplePurchaseEnvironment = "Production" | "Sandbox";

type AppleIAPCredentials = {
  issuerID: string;
  keyID: string;
  privateKey: CryptoKey;
};

const appleHosts: Record<ApplePurchaseEnvironment, string> = {
  Production: "https://api.storekit.apple.com",
  Sandbox: "https://api.storekit-sandbox.apple.com",
};
const transactionNotFoundCode = 4040010;

export class AppleTransactionNotFound extends Error {}

export async function loadAppleIAPCredentials(
  issuer: string | undefined,
  key: string | undefined,
  pem: string | undefined,
): Promise<AppleIAPCredentials | null> {
  const issuerID = issuer?.trim() ?? "";
  const keyID = key?.trim() ?? "";
  if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(issuerID) ||
      !/^[A-Z0-9]{10}$/.test(keyID)) return null;

  const body = pem?.trim().match(/^-----BEGIN PRIVATE KEY-----\r?\n([A-Za-z0-9+/=\r\n]+)\r?\n-----END PRIVATE KEY-----$/)?.[1];
  if (!body || body.length > 2048) return null;
  const encoded = body.replace(/[\r\n]/g, "");
  const bytes = Buffer.from(encoded, "base64");
  if (bytes.toString("base64") !== encoded) return null;

  try {
    const privateKey = await crypto.subtle.importKey(
      "pkcs8", bytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
    );
    return { issuerID, keyID, privateKey };
  } catch {
    return null;
  }
}

async function requestToken(bundleID: string, credentials: AppleIAPCredentials): Promise<string> {
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: credentials.keyID, typ: "JWT" };
  const claims = { iss: credentials.issuerID, iat: issuedAt, exp: issuedAt + 120, aud: "appstoreconnect-v1", bid: bundleID };
  const input = [header, claims].map(value => Buffer.from(JSON.stringify(value)).toString("base64url")).join(".");
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, credentials.privateKey, new TextEncoder().encode(input),
  );
  return input + "." + Buffer.from(signature).toString("base64url");
}

export function isAppleTransactionJWS(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value);
}

async function requestAppleTransaction(
  transactionID: string,
  environment: ApplePurchaseEnvironment,
  bundleID: string,
  credentials: AppleIAPCredentials,
  fetchTransaction: typeof fetch,
): Promise<string | null> {
  const token = await requestToken(bundleID, credentials);
  const url = appleHosts[environment] + "/inApps/v1/transactions/" + encodeURIComponent(transactionID);
  const response = await fetchTransaction(url, {
    method: "GET",
    headers: { Authorization: "Bearer " + token, Accept: "application/json" },
    redirect: "error",
    signal: AbortSignal.timeout(6_000),
  });
  if (response.status !== 200 && response.status !== 404) throw new Error("Apple transaction lookup failed");
  const text = await response.text();
  if (text.length > 32768) throw new Error("Invalid Apple response");
  const body = JSON.parse(text);
  if (response.status === 404 && body?.errorCode === transactionNotFoundCode) return null;
  if (response.status !== 200 || !isAppleTransactionJWS(body?.signedTransactionInfo)) {
    throw new Error("Invalid Apple response");
  }
  return body.signedTransactionInfo;
}

export async function lookupAppleTransaction(
  transactionID: string,
  hint: ApplePurchaseEnvironment,
  bundleID: string,
  credentials: AppleIAPCredentials,
  fetchTransaction: typeof fetch = fetch,
): Promise<{ signedTransaction: string; environment: ApplePurchaseEnvironment }> {
  const alternate = hint === "Production" ? "Sandbox" : "Production";
  for (const environment of [hint, alternate] as const) {
    const signedTransaction = await requestAppleTransaction(transactionID, environment, bundleID, credentials, fetchTransaction);
    if (signedTransaction !== null) return { environment, signedTransaction };
  }
  throw new AppleTransactionNotFound();
}
