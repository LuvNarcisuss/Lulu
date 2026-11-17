import { Buffer } from "node:buffer";

type ReceiptExpectation = {
  bundleID: string;
  transactionID: string;
  productID: string;
  accountID: string;
  sandboxOnly: boolean;
  appleAppID?: number;
};

type VerifiedReceiptPurchase = {
  environment: "Production" | "Sandbox";
  transactionID: string;
  productID: string;
};

export class AppleReceiptRejected extends Error {}
export class AppleReceiptUnavailable extends Error {}
const maxReceiptLength = 1_400_000;
const rejection = () => new AppleReceiptRejected("Apple receipt does not match this purchase");
const record = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);

async function requestReceipt(encoded: string, sandbox: boolean, fetcher: typeof fetch): Promise<Record<string, unknown>> {
  const url = sandbox ? "https://sandbox.itunes.apple.com/verifyReceipt" : "https://buy.itunes.apple.com/verifyReceipt";
  try {
    const response = await fetcher(url, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(8_000),
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      // Consumables require neither a subscription shared secret nor a .p8 key.
      body: JSON.stringify({ "receipt-data": encoded }),
    });
    if (!response.ok) throw new Error("Apple receipt service unavailable");
    const text = await response.text();
    if (text.length > 4_000_000) throw new Error("Apple receipt response too large");
    const body: unknown = JSON.parse(text);
    if (!record(body) || !Number.isInteger(body.status)) throw new Error("Invalid Apple receipt response");
    return body;
  } catch {
    throw new AppleReceiptUnavailable("Apple receipt verification temporarily unavailable");
  }
}

export async function verifyAppleReceipt(
  encoded: unknown, expected: ReceiptExpectation, fetcher: typeof fetch = fetch,
): Promise<VerifiedReceiptPurchase> {
  if (typeof encoded !== "string" || encoded.length === 0 || encoded.length > maxReceiptLength ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded) || encoded.length % 4 !== 0 ||
      Buffer.from(encoded, "base64").toString("base64") !== encoded) throw rejection();
  let body = await requestReceipt(encoded, false, fetcher);
  let sandbox = false;
  // Always try production first so App Review does not depend on a client hint.
  if (body.status === 21007) {
    sandbox = true;
    body = await requestReceipt(encoded, true, fetcher);
  }
  const status = body.status as number;
  if (status === 21005 || status === 21009 || (status >= 21100 && status <= 21199)) {
    throw new AppleReceiptUnavailable("Apple receipt verification temporarily unavailable");
  }
  if (status !== 0) throw rejection();
  const environment = sandbox ? "Sandbox" : "Production";
  const receipt = body.receipt;
  if (body.environment !== environment || (expected.sandboxOnly && !sandbox) || !record(receipt) ||
      receipt.bundle_id !== expected.bundleID ||
      receipt.receipt_type !== (sandbox ? "ProductionSandbox" : "Production") ||
      (!sandbox && expected.appleAppID !== undefined && receipt.app_item_id !== expected.appleAppID) ||
      !Array.isArray(receipt.in_app)) throw rejection();

  // Match only the requested transaction; never credit every row in an app receipt.
  const matches = receipt.in_app.filter((row): row is Record<string, unknown> =>
    record(row) && row.transaction_id === expected.transactionID);
  if (matches.length !== 1) throw rejection();
  const purchase = matches[0];
  const latest = Array.isArray(body.latest_receipt_info) ? body.latest_receipt_info.filter(
    (row): row is Record<string, unknown> => record(row) && row.transaction_id === expected.transactionID,
  ) : [];
  for (const row of [purchase, ...latest]) {
    if (row.product_id !== expected.productID || (row.quantity !== "1" && row.quantity !== 1) ||
        row.cancellation_date != null || row.cancellation_date_ms != null || row.cancellation_reason != null ||
        row.revocation_date != null || row.revocation_date_ms != null || row.expires_date != null || row.expires_date_ms != null ||
        (row.in_app_ownership_type != null && row.in_app_ownership_type !== "PURCHASED") ||
        (row.app_account_token != null && (typeof row.app_account_token !== "string" ||
          row.app_account_token.toLowerCase() !== expected.accountID.toLowerCase()))) throw rejection();
  }
  if (typeof purchase.purchase_date_ms !== "string" || !/^[0-9]{1,16}$/.test(purchase.purchase_date_ms) ||
      Number(purchase.purchase_date_ms) <= 0) throw rejection();
  // Legacy consumable receipts may omit app_account_token. The authenticated
  // claimant is bound by the atomic ledger; another account cannot claim it again.
  return { environment, transactionID: expected.transactionID, productID: expected.productID };
}
