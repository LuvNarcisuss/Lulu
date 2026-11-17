import { Buffer } from "node:buffer";
import { verify as verifySignature } from "node:crypto";
import { BitString, ObjectIdentifier, OctetString } from "npm:asn1js@4.0.0";
import {
  type AlgorithmIdentifier,
  BasicConstraints,
  BasicOCSPResponse,
  Certificate,
  CertID,
  CryptoEngine,
  ExtKeyUsage,
  InfoAccess,
  OCSPRequest,
  OCSPResponse,
  type PublicKeyInfo,
  RelativeDistinguishedNames,
  Request as OCSPEntry,
  TBSRequest,
  id_PKIX_OCSP_Basic,
} from "npm:pkijs@4.0.1";

class AppleCryptoEngine extends CryptoEngine {
  override async verifyWithPublicKey(
    data: BufferSource,
    signature: BitString | OctetString,
    key: PublicKeyInfo,
    algorithm: AlgorithmIdentifier,
    hash?: string,
  ): Promise<boolean> {
    const curve = key.algorithm.algorithmParams;
    // Apple's G3 OCSP responder certificate uses P-384 with SHA-256.
    // Deno 2.1 Web Crypto rejects that pair, but its direct signature API supports it.
    if (algorithm.algorithmId === "1.2.840.10045.4.3.2" &&
        key.algorithm.algorithmId === "1.2.840.10045.2.1" &&
        curve instanceof ObjectIdentifier && curve.valueBlock.toString() === "1.3.132.0.34") {
      const bytes = ArrayBuffer.isView(data)
        ? Buffer.from(data.buffer, data.byteOffset, data.byteLength)
        : Buffer.from(data);
      const publicKey = { key: Buffer.from(key.toSchema().toBER()), type: "spki" as const, format: "der" as const };
      return verifySignature("sha256", bytes, publicKey, signature.valueBlock.valueHexView);
    }
    return await super.verifyWithPublicKey(data, signature, key, algorithm, hash);
  }
}

const engine = new AppleCryptoEngine({ name: "Web Crypto", crypto: globalThis.crypto });
const signingCertificate = "1.2.840.113635.100.6.11.1";
const signingAuthority = "1.2.840.113635.100.6.2.1";
const basicConstraints = "2.5.29.19";
const keyUsage = "2.5.29.15";
const authorityInfoAccess = "1.3.6.1.5.5.7.1.1";
const ocspAccessMethod = "1.3.6.1.5.5.7.48.1";
const ocspSigning = "1.3.6.1.5.5.7.3.9";
const extendedKeyUsage = "2.5.29.37";
const appleOCSPHosts = new Set(["ocsp.apple.com", "ocsp2.apple.com"]);
const clockSkew = 60_000;
const maxOCSPBytes = 65_536;

// Transport and responder outages are retryable, but can never grant credit.
export class AppleVerificationUnavailable extends Error {}

type VerificationOptions = {
  trustedRoot: BufferSource;
  fetchStatus?: typeof fetch;
  now?: () => Date;
};

function extension(certificate: Certificate, oid: string) {
  return certificate.extensions?.find(item => item.extnID === oid);
}

function isCA(certificate: Certificate): boolean {
  const constraints = extension(certificate, basicConstraints)?.parsedValue;
  return constraints instanceof BasicConstraints && constraints.cA;
}

function permitsKeyUsage(certificate: Certificate, usage: number): boolean {
  const field = extension(certificate, keyUsage);
  if (!field) return true;
  const bits = field.parsedValue;
  return bits instanceof BitString && (bits.valueBlock.valueHexView[0] & usage) !== 0;
}

function validAt(certificate: Certificate, now: number): boolean {
  return certificate.notBefore.value.getTime() <= now + clockSkew &&
    certificate.notAfter.value.getTime() >= now - clockSkew;
}

async function issuedBy(certificate: Certificate, issuer: Certificate): Promise<boolean> {
  return certificate.issuer.isEqual(issuer.subject) && await certificate.verify(issuer, engine);
}

function ocspURL(certificate: Certificate): URL {
  const access = extension(certificate, authorityInfoAccess)?.parsedValue;
  if (!(access instanceof InfoAccess)) throw new Error("Missing Apple certificate status endpoint");
  for (const description of access.accessDescriptions) {
    const location = description.accessLocation;
    if (description.accessMethod !== ocspAccessMethod || location.type !== 6) continue;
    const url = new URL(location.value);
    if ((url.protocol === "http:" || url.protocol === "https:") && appleOCSPHosts.has(url.hostname) &&
        !url.username && !url.password && !url.port && !url.hash) return url;
  }
  throw new Error("Invalid Apple certificate status endpoint");
}

async function fetchOCSP(url: URL, request: ArrayBuffer, fetchStatus: typeof fetch): Promise<ArrayBuffer> {
  try {
    const response = await fetchStatus(url, {
      method: "POST",
      headers: { "Content-Type": "application/ocsp-request", "Accept": "application/ocsp-response" },
      body: request,
      redirect: "error",
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok || !response.body) throw new AppleVerificationUnavailable();
    const reader = response.body.getReader();
    const bytes = new Uint8Array(maxOCSPBytes);
    let length = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) return bytes.buffer.slice(0, length);
        if (length + value.byteLength > maxOCSPBytes) throw new AppleVerificationUnavailable();
        bytes.set(value, length);
        length += value.byteLength;
      }
    } finally {
      await reader.cancel();
    }
  } catch {
    throw new AppleVerificationUnavailable();
  }
}

async function responseSignerMatches(signer: Certificate, id: BasicOCSPResponse["tbsResponseData"]["responderID"]): Promise<boolean> {
  if (id instanceof RelativeDistinguishedNames) return id.isEqual(signer.subject);
  if (!(id instanceof OctetString)) return false;
  // RFC 6960 defines a by-key responder ID as SHA-1 of the public key bits.
  const keyBits = signer.subjectPublicKeyInfo.subjectPublicKey.valueBlock.valueHexView;
  const keyHash = await engine.digest("SHA-1", keyBits);
  return Buffer.from(keyHash).equals(Buffer.from(id.valueBlock.valueHexView));
}

async function validOCSPSignature(response: BasicOCSPResponse, issuer: Certificate, now: number): Promise<boolean> {
  const algorithm = engine.getAlgorithmByOID(response.signatureAlgorithm.algorithmId, true) as { hash?: Algorithm };
  if (!algorithm.hash || !["SHA-256", "SHA-384", "SHA-512"].includes(algorithm.hash.name)) return false;
  for (const signer of [issuer, ...(response.certs ?? [])]) {
    if (!await responseSignerMatches(signer, response.tbsResponseData.responderID)) continue;
    if (signer !== issuer) {
      const usage = extension(signer, extendedKeyUsage)?.parsedValue;
      if (!(usage instanceof ExtKeyUsage) || !usage.keyPurposes.includes(ocspSigning) ||
          !permitsKeyUsage(signer, 0x80) || !validAt(signer, now) || !await issuedBy(signer, issuer)) continue;
    }
    if (await engine.verifyWithPublicKey(
      response.tbsResponseData.tbsView,
      response.signature,
      signer.subjectPublicKeyInfo,
      response.signatureAlgorithm,
    )) return true;
  }
  return false;
}

async function requireGoodOCSP(
  certificate: Certificate,
  issuer: Certificate,
  now: number,
  fetchStatus: typeof fetch,
): Promise<void> {
  const id = new CertID();
  await id.createForCertificate(certificate, { hashAlgorithm: "SHA-256", issuerCertificate: issuer }, engine);
  const request = new OCSPRequest({ tbsRequest: new TBSRequest({ requestList: [new OCSPEntry({ reqCert: id })] }) });
  const body = await fetchOCSP(ocspURL(certificate), request.toSchema(true).toBER(), fetchStatus);
  const response = OCSPResponse.fromBER(body);
  if ([2, 3].includes(response.responseStatus.valueBlock.valueDec)) throw new AppleVerificationUnavailable();
  if (response.responseStatus.valueBlock.valueDec !== 0 || response.responseBytes?.responseType !== id_PKIX_OCSP_Basic) {
    throw new Error("Invalid Apple certificate status response");
  }
  const basic = BasicOCSPResponse.fromBER(response.responseBytes.response.valueBlock.valueHexView);
  if (!await validOCSPSignature(basic, issuer, now)) throw new Error("Invalid Apple certificate status signature");
  const matches = basic.tbsResponseData.responses.filter(item => item.certID.isEqual(id));
  if (matches.length !== 1) throw new Error("Invalid Apple certificate status identifier");
  const { certStatus, thisUpdate, nextUpdate } = matches[0];
  if (certStatus.idBlock.tagClass !== 3 || certStatus.idBlock.tagNumber !== 0 || certStatus.idBlock.isConstructed ||
      certStatus.valueBlock.valueHexView.byteLength !== 0 ||
      !(basic.tbsResponseData.producedAt.getTime() <= now + clockSkew) ||
      !(thisUpdate.getTime() <= now + clockSkew) || !(nextUpdate && nextUpdate.getTime() >= now - clockSkew) ||
      nextUpdate.getTime() < thisUpdate.getTime()) {
    throw new Error("Apple certificate status is not current and good");
  }
}

function jsonObject(value: string): Record<string, unknown> {
  const result: unknown = JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
  if (!result || typeof result !== "object" || Array.isArray(result)) throw new Error("Invalid Apple transaction data");
  return result as Record<string, unknown>;
}

/**
 * Verify Apple's transaction signing purpose, certificate chain, live certificate
 * status and ES256 signature using Web Crypto on the Edge Runtime.
 */
export async function verifyAppleTransaction(
  signed: string,
  { trustedRoot, fetchStatus = fetch, now = () => new Date() }: VerificationOptions,
): Promise<Record<string, unknown>> {
  const parts = signed.split(".");
  if (parts.length !== 3 || parts.some(part => !/^[A-Za-z0-9_-]+$/.test(part))) throw new Error("Invalid Apple transaction");
  const [headerBytes, payloadBytes, signatureBytes] = parts;
  const header = jsonObject(headerBytes);
  const chain = header.x5c;
  if (header.alg !== "ES256" || header.crit !== undefined || !Array.isArray(chain) || chain.length !== 3 ||
      chain.some(certificate => typeof certificate !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(certificate))) {
    throw new Error("Invalid Apple signing certificate chain");
  }
  // The caller pins the trusted root. The root supplied in the JWS is never trusted.
  const leaf = Certificate.fromBER(Buffer.from(chain[0], "base64"));
  const issuer = Certificate.fromBER(Buffer.from(chain[1], "base64"));
  const root = Certificate.fromBER(trustedRoot);
  const verificationTime = now().getTime();
  if (!extension(leaf, signingCertificate) || !extension(issuer, signingAuthority) ||
      isCA(leaf) || !isCA(issuer) || !isCA(root) ||
      !permitsKeyUsage(leaf, 0x80) || !permitsKeyUsage(issuer, 0x04) ||
      ![leaf, issuer, root].every(certificate => validAt(certificate, verificationTime)) ||
      !await issuedBy(issuer, root) || !await issuedBy(leaf, issuer)) {
    throw new Error("Invalid Apple signing certificate chain");
  }
  const key = await crypto.subtle.importKey("spki", leaf.subjectPublicKeyInfo.toSchema().toBER(), {
    name: "ECDSA", namedCurve: "P-256",
  }, false, ["verify"]);
  const signature = Buffer.from(signatureBytes, "base64url");
  if (signature.length !== 64 || !await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    signature,
    new TextEncoder().encode(headerBytes + "." + payloadBytes),
  )) throw new Error("Invalid Apple transaction signature");
  const payload = jsonObject(payloadBytes);
  const statuses = await Promise.allSettled([
    requireGoodOCSP(leaf, issuer, verificationTime, fetchStatus),
    requireGoodOCSP(issuer, root, verificationTime, fetchStatus),
  ]);
  for (const status of statuses) {
    if (status.status === "rejected") throw status.reason;
  }
  return payload;
}
