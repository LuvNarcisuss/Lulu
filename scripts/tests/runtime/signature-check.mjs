import {SignedDataVerifier,Environment} from '@apple/app-store-server-library';
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const root = process.env.LULU_PROJECT_ROOT ?? new URL('../../../', import.meta.url).pathname;
const src=readFileSync(root+'supabase/functions/travel-coin-purchase/index.ts','utf8');
const appleRoot=Buffer.from(src.match(/const appleRoot = Buffer.from\("([^"]+)"/)[1],'base64');
let count=0;
for(const env of [Environment.SANDBOX,Environment.PRODUCTION]){
 const verifier=new SignedDataVerifier([appleRoot],true,env,'com.lulu.tourtravel',env===Environment.PRODUCTION?6832914128:undefined);
 const payload={environment:env,bundleId:'com.lulu.tourtravel',productId:'iltpkpefqtjskxel',transactionId:'1',type:'Consumable',quantity:1,signedDate:Date.now()};
 const jws=Buffer.from(JSON.stringify({alg:'ES256',x5c:[]})).toString('base64url')+'.'+Buffer.from(JSON.stringify(payload)).toString('base64url')+'.Zm9yZ2Vk';
 await assert.rejects(()=>verifier.verifyAndDecodeTransaction(jws));count++;
}
console.log(JSON.stringify({passed:count,scope:'Apple library rejects forged Sandbox and Production transactions; no real purchase performed'}));
