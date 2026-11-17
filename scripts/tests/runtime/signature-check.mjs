import * as asn1 from "asn1js";
import assert from "node:assert/strict";
import { sign as signWithDigest } from "node:crypto";
import { registerHooks } from "node:module";
import test from "node:test";
import * as pki from "pkijs";

// Load the Edge source directly under Node's Web Crypto implementation.
registerHooks({
  resolve(specifier, context, nextResolve) {
    const dependency = /^npm:(asn1js|pkijs)@/.exec(specifier);
    return dependency
      ? nextResolve(dependency[1], { ...context, parentURL: import.meta.url })
      : nextResolve(specifier, context);
  },
});

const { verifyAppleTransaction, AppleVerificationUnavailable } = await import(
  new URL("../../../supabase/functions/travel-coin-purchase/apple-transaction.ts", import.meta.url)
);

const verificationTime = new Date("2026-11-17T12:00:00Z");
const minute = 60_000;
const bundleId = "com.lulu.tourtravel";
const payload = {
  environment: "Sandbox",
  bundleId,
  productId: "iltpkpefqtjskxel",
  appAccountToken: "00000000-0000-4000-8000-000000000001",
  transactionId: "100001",
  type: "Consumable",
  inAppOwnershipType: "PURCHASED",
  quantity: 1,
};
let serial = 0;

class FixtureSigningEngine extends pki.CryptoEngine {
  async sign(algorithm, key, bytes) {
    // Recreate Apple's P-384 issuer with a SHA-256-signed OCSP responder.
    if (key.algorithm.namedCurve === "P-384" && algorithm.hash.name === "SHA-256") {
      const privateKey = {
        key: Buffer.from(await crypto.subtle.exportKey("pkcs8", key)),
        type: "pkcs8", format: "der",
      };
      const signature = signWithDigest("sha256", bytes, privateKey);
      return pki.createECDSASignatureFromCMS(asn1.fromBER(signature).result, 48);
    }
    return await super.sign(algorithm, key, bytes);
  }
}

const fixtureSigning = new FixtureSigningEngine({ name: "Test signing", crypto });

function extension(extnID, value) {
  return new pki.Extension({ extnID, extnValue: value.toBER() });
}

async function identity(name, issuer, { ca = false, purpose, ocspPath, responder = false } = {}) {
  const keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: ca ? "P-384" : "P-256" }, true, ["sign", "verify"]);
  const certificate = new pki.Certificate({
    version: 2,
    serialNumber: new asn1.Integer({ value: ++serial }),
    extensions: [
      extension("2.5.29.19", new pki.BasicConstraints({ cA: ca }).toSchema()),
      extension("2.5.29.15", new asn1.BitString({ valueHex: Uint8Array.of(ca ? 0x04 : 0x80).buffer })),
    ],
  });
  certificate.subject.typesAndValues.push(new pki.AttributeTypeAndValue({
    type: "2.5.4.3", value: new asn1.Utf8String({ value: name }),
  }));
  certificate.issuer = issuer?.certificate.subject ?? certificate.subject;
  certificate.notBefore.value = new Date(verificationTime.valueOf() - 60 * minute);
  certificate.notAfter.value = new Date(verificationTime.valueOf() + 60 * minute);
  if (purpose) certificate.extensions.push(extension(purpose, new asn1.Null()));
  if (responder) {
    certificate.extensions.push(extension("2.5.29.37", new pki.ExtKeyUsage({
      keyPurposes: ["1.3.6.1.5.5.7.3.9"],
    }).toSchema()));
  }
  if (ocspPath) {
    certificate.extensions.push(extension("1.3.6.1.5.5.7.1.1", new pki.InfoAccess({
      accessDescriptions: [new pki.AccessDescription({
        accessMethod: "1.3.6.1.5.5.7.48.1",
        accessLocation: new pki.GeneralName({ type: 6, value: "http://ocsp.apple.com/" + ocspPath }),
      })],
    }).toSchema()));
  }
  await certificate.subjectPublicKeyInfo.importKey(keys.publicKey);
  await certificate.sign(issuer?.keys.privateKey ?? keys.privateKey, responder ? "SHA-256" : "SHA-384", fixtureSigning);
  return { certificate, keys };
}

const trust = await identity("Isolated root", undefined, { ca: true });
const issuer = await identity("Isolated intermediate", trust, {
  ca: true, purpose: "1.2.840.113635.100.6.2.1", ocspPath: "test-intermediate",
});
const leaf = await identity("Isolated App Store signer", issuer, {
  purpose: "1.2.840.113635.100.6.11.1", ocspPath: "test-leaf",
});
const delegate = await identity("Isolated authorized OCSP responder", issuer, { responder: true });
const unauthorized = await identity("Isolated non-OCSP certificate", issuer);
const foreignRoot = await identity("Another isolated root", undefined, { ca: true });

function encoded(certificate) {
  return Buffer.from(certificate.toSchema().toBER()).toString("base64");
}

async function token({ signer = leaf, body = payload, chain = [leaf, issuer, trust], alg = "ES256" } = {}) {
  const header = Buffer.from(JSON.stringify({ alg, x5c: chain.map(item => encoded(item.certificate)) })).toString("base64url");
  const data = Buffer.from(JSON.stringify(body)).toString("base64url");
  const input = header + "." + data;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, signer.keys.privateKey, new TextEncoder().encode(input));
  return input + "." + Buffer.from(signature).toString("base64url");
}

async function status(certificate, authority, {
  signer = authority,
  statusTag = 0,
  thisUpdate = new Date(verificationTime.valueOf() - minute),
  nextUpdate = new Date(verificationTime.valueOf() + minute),
} = {}) {
  const certID = new pki.CertID();
  await certID.createForCertificate(certificate.certificate, {
    hashAlgorithm: "SHA-256", issuerCertificate: authority.certificate,
  });
  const basic = new pki.BasicOCSPResponse();
  basic.tbsResponseData.responderID = authority === signer
    ? signer.certificate.subject
    : new asn1.OctetString({ valueHex: await crypto.subtle.digest(
      "SHA-1", signer.certificate.subjectPublicKeyInfo.subjectPublicKey.valueBlock.valueHexView,
    ) });
  basic.tbsResponseData.producedAt = thisUpdate;
  const certStatus = statusTag === 1
    ? new asn1.Constructed({
      idBlock: { tagClass: 3, tagNumber: 1 },
      value: [new asn1.GeneralizedTime({ valueDate: thisUpdate })],
    })
    : new asn1.Primitive({ idBlock: { tagClass: 3, tagNumber: statusTag } });
  basic.tbsResponseData.responses = [new pki.SingleResponse({
    certID,
    certStatus,
    thisUpdate,
    nextUpdate,
  })];
  if (authority !== signer) basic.certs = [signer.certificate];
  const hash = signer.keys.privateKey.algorithm.namedCurve === "P-384" ? "SHA-384" : "SHA-256";
  await basic.sign(signer.keys.privateKey, hash);
  return new pki.OCSPResponse({
    responseStatus: new asn1.Enumerated({ value: 0 }),
    responseBytes: new pki.ResponseBytes({
      responseType: pki.id_PKIX_OCSP_Basic,
      response: new asn1.OctetString({ valueHex: basic.toSchema().toBER() }),
    }),
  }).toSchema().toBER();
}

function verify(signed, { leafStatus = {}, expectedEnvironment = "Sandbox", trustedRoot = trust, offline = false } = {}) {
  const seen = [];
  const result = verifyAppleTransaction(signed, {
    trustedRoot: Buffer.from(encoded(trustedRoot.certificate), "base64"),
    now: () => verificationTime,
    fetchStatus: async (url, request) => {
      assert.equal(request.method, "POST");
      assert.equal(request.redirect, "error");
      const ocsp = pki.OCSPRequest.fromBER(request.body);
      assert.equal(ocsp.tbsRequest.requestList.length, 1);
      const isLeaf = url.pathname === "/test-leaf";
      assert.equal(url.href, "http://ocsp.apple.com/" + (isLeaf ? "test-leaf" : "test-intermediate"));
      seen.push(url.pathname);
      if (offline) return new Response(null, { status: 503 });
      return new Response(isLeaf ? await status(leaf, issuer, leafStatus) : await status(issuer, trust));
    },
  }).then(transaction => {
    assert.deepEqual(seen.sort(), ["/test-intermediate", "/test-leaf"]);
    assert.equal(transaction.environment, expectedEnvironment);
    return transaction;
  });
  return result;
}

test("accepts an ES256 purchase with an issuer-signed and a delegated good OCSP response", async () => {
  assert.deepEqual(await verify(await token(), { leafStatus: { signer: delegate } }), payload);
});

test("production uses the same cryptographic verification", async () => {
  const production = { ...payload, environment: "Production" };
  assert.deepEqual(await verify(await token({ body: production }), { expectedEnvironment: "Production" }), production);
});

test("rejects a forged transaction signature regardless of matching claims", async () => {
  await assert.rejects(verify(await token({ signer: unauthorized })));
});

test("rejects a non-ES256 header and an untrusted certificate chain", async () => {
  await assert.rejects(verify(await token({ alg: "ES384" })));
  await assert.rejects(verify(await token(), { trustedRoot: foreignRoot }));
});

test("rejects revoked, unknown, or stale OCSP status and an unauthorized responder", async () => {
  const signed = await token();
  await assert.rejects(verify(signed, { leafStatus: { statusTag: 1 } }));
  await assert.rejects(verify(signed, { leafStatus: { statusTag: 2 } }));
  await assert.rejects(verify(signed, { leafStatus: { nextUpdate: new Date(verificationTime.valueOf() - 10 * minute) } }));
  await assert.rejects(verify(signed, { leafStatus: { signer: unauthorized } }));
});

test("treats an unreachable Apple status endpoint as a retryable failure", async () => {
  await assert.rejects(verify(await token(), { offline: true }), AppleVerificationUnavailable);
});
