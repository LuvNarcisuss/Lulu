import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyAppleReceipt, AppleReceiptRejected, AppleReceiptUnavailable } from '../../supabase/functions/travel-coin-purchase/apple-receipt.ts';

const account = '00000000-0000-4000-8000-000000000001';
const receiptData = Buffer.from('synthetic receipt transport fixture').toString('base64');
const purchase = { transaction_id: '100001', original_transaction_id: '100001', product_id: 'neiku_30', quantity: '1', purchase_date_ms: '1794800000000' };
const expected = { bundleID: 'im.seex.sao2', transactionID: '100001', productID: 'neiku_30', accountID: account, sandboxOnly: true };
function fixture(environment = 'Sandbox', row = {}) {
  return { status: 0, environment, receipt: { bundle_id: expected.bundleID, receipt_type: environment === 'Sandbox' ? 'ProductionSandbox' : 'Production', in_app: [{ ...purchase, ...row }] } };
}
function responses(...bodies) {
  const urls = [];
  return { urls, fetcher: async (url, init) => {
    urls.push(url);
    assert.equal(init.method, 'POST');
    assert.equal(init.redirect, 'error');
    assert.ok(init.signal instanceof AbortSignal);
    assert.deepEqual(JSON.parse(init.body), { 'receipt-data': receiptData });
    assert.equal(new Headers(init.headers).get('Authorization'), null);
    const body = bodies.shift();
    if (body instanceof Error) throw body;
    return new Response(JSON.stringify(body), { status: 200 });
  } };
}

test('consumable receipt uses production then 21007 sandbox without API key or subscription password', async () => {
  const network = responses({ status: 21007 }, fixture());
  assert.deepEqual(await verifyAppleReceipt(receiptData, expected, network.fetcher), {
    environment: 'Sandbox', transactionID: '100001', productID: 'neiku_30',
  });
  assert.deepEqual(network.urls, ['https://buy.itunes.apple.com/verifyReceipt', 'https://sandbox.itunes.apple.com/verifyReceipt']);
});

test('formal production receipt selects production independent of client environment hint', async () => {
  const body = fixture('Production'); body.receipt.bundle_id = 'com.lulu.tourtravel'; body.receipt.app_item_id = 6832914128;
  const network = responses(body);
  const result = await verifyAppleReceipt(receiptData, { ...expected, bundleID: 'com.lulu.tourtravel', sandboxOnly: false, appleAppID: 6832914128 }, network.fetcher);
  assert.equal(result.environment, 'Production');
  assert.equal(network.urls.length, 1);
});

for (const [name, change] of [
  ['wrong bundle', b => b.receipt.bundle_id = 'other.app'],
  ['wrong transaction', b => b.receipt.in_app[0].transaction_id = '200002'],
  ['wrong product', b => b.receipt.in_app[0].product_id = 'otherproduct'],
  ['wrong quantity', b => b.receipt.in_app[0].quantity = '2'],
  ['refund', b => b.receipt.in_app[0].cancellation_date_ms = '1794800001000'],
  ['revocation', b => b.receipt.in_app[0].cancellation_reason = '1'],
  ['subscription', b => b.receipt.in_app[0].expires_date_ms = '1794900001000'],
  ['family sharing', b => b.receipt.in_app[0].in_app_ownership_type = 'FAMILY_SHARED'],
  ['wrong signed account', b => b.receipt.in_app[0].app_account_token = '00000000-0000-4000-8000-000000000002'],
  ['missing purchase date', b => delete b.receipt.in_app[0].purchase_date_ms],
  ['empty purchases', b => b.receipt.in_app = []],
  ['wrong environment', b => b.environment = 'Xcode'],
  ['wrong receipt type', b => b.receipt.receipt_type = 'Production'],
]) {
  test(`verified receipt rejects ${name}`, async () => {
    const body = fixture(); change(body);
    const network = responses({ status: 21007 }, body);
    await assert.rejects(verifyAppleReceipt(receiptData, expected, network.fetcher), AppleReceiptRejected);
  });
}

test('test bundle cannot credit a production receipt', async () => {
  await assert.rejects(verifyAppleReceipt(receiptData, expected, responses(fixture('Production')).fetcher), AppleReceiptRejected);
});

test('a matching Apple account token is accepted but a conflicting latest-info token is rejected', async () => {
  let body = fixture('Sandbox', { app_account_token: account.toUpperCase() });
  await verifyAppleReceipt(receiptData, expected, responses({ status: 21007 }, body).fetcher);
  body = fixture();
  body.latest_receipt_info = [{ ...purchase, app_account_token: '00000000-0000-4000-8000-000000000002' }];
  await assert.rejects(verifyAppleReceipt(receiptData, expected, responses({ status: 21007 }, body).fetcher), AppleReceiptRejected);
});

for (const status of [21002, 21003, 21004, 21006, 21008, 21010]) {
  test(`Apple rejection ${status} never becomes a verified purchase`, async () => {
    const network = responses({ status });
    await assert.rejects(verifyAppleReceipt(receiptData, expected, network.fetcher), AppleReceiptRejected);
    assert.equal(network.urls.length, 1);
  });
}
for (const status of [21005, 21009, 21100]) {
  test(`Apple outage ${status} remains recoverable`, async () => {
    await assert.rejects(verifyAppleReceipt(receiptData, expected, responses({ status }).fetcher), AppleReceiptUnavailable);
  });
}

test('malformed receipt is rejected before network and network failures cannot verify', async () => {
  const network = responses();
  for (const value of ['', '%%%bad', 'A'.repeat(1_400_001)]) await assert.rejects(verifyAppleReceipt(value, expected, network.fetcher), AppleReceiptRejected);
  assert.equal(network.urls.length, 0);
  await assert.rejects(verifyAppleReceipt(receiptData, expected, responses(new Error('offline')).fetcher), AppleReceiptUnavailable);
});
