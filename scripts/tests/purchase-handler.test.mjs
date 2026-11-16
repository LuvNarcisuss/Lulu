import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
const root = new URL('../../', import.meta.url);
const source = readFileSync(new URL('supabase/functions/travel-coin-purchase/index.ts', root), 'utf8');
const account = '00000000-0000-4000-8000-000000000001';
const products = ['iltpkpefqtjskxel','eweerqrczkwsjyjn','bfktecvbuyjzwxtp','zsadvhodvgamjqqp','qtqrufubdpyvzjzs','ipcijraguygtcpsa','azjrhiwubtjsrbzh','qjcdfljcmzajynnd','rzeethasxinmprew'];
function harness({environment='Sandbox',bundle='com.lulu.tourtravel',product=products[0],owner=account,appleID='6832914128',verificationFails=false,ledgerFails=false}={}) {
 const calls=[];let handler;
 const payload={environment,bundleId:bundle,productId:product,appAccountToken:owner,transactionId:'100001',quantity:1,type:'Consumable',inAppOwnershipType:'PURCHASED'};
 class Verifier {constructor(roots,checks,env,bid,id){this.env=env;this.bundle=bid;assert.equal(checks,true);} async verifyAndDecodeTransaction(){if(verificationFails||this.env!==payload.environment||this.bundle!==payload.bundleId)throw Error('Rejected signature or identity');return payload;}}
 const client={auth:{getUser:async()=>({data:{user:{id:account}},error:null})},rpc:async(name,args)=>{calls.push({name,args});return {data:{committed:true},error:ledgerFails?{message:'Unavailable'}:null};}};
 const env={SUPABASE_URL:'https://example.supabase.co',SUPABASE_ANON_KEY:'test-public',SUPABASE_SERVICE_ROLE_KEY:'test-service',APPLE_APP_ID:appleID};
 const js=stripTypeScriptTypes(source.replace(/^import .*;\n/gm,''));
 vm.runInNewContext(js,{Buffer,Response,Request,JSON,Number,Boolean,Error,console,Environment:{PRODUCTION:'Production',SANDBOX:'Sandbox'},SignedDataVerifier:Verifier,createClient:()=>client,Deno:{env:{get:k=>env[k]},serve:f=>handler=f}});
 return {calls,request:async(input)=>{const response=await handler(new Request('https://example.test',{method:'POST',headers:{Authorization:'Bearer test-user'},body:JSON.stringify(input)}));return {status:response.status,body:await response.json()};}};
}
test('sandbox readiness does not depend on production APPLE_APP_ID secret',async()=>{
 const h=harness({appleID:''}); const r=await h.request({action:'status',bundle_id:'com.lulu.tourtravel',environment:'Sandbox'});assert.equal(r.body.available,true);
});
test('unknown bundle is rejected before offering checkout',async()=>{
 const r=await harness().request({action:'status',bundle_id:'com.other.app',environment:'Sandbox'});assert.equal(r.body.available,false);
});
for(const product of products)test(`verified sandbox ${product} uses only sandbox ledger`,async()=>{
 const h=harness({product});const r=await h.request({action:'deliver',signed_transaction:'e30.eyJ0ZXN0Ijp0cnVlfQ.c2ln',bundle_id:'com.lulu.tourtravel',environment:'Sandbox'});assert.equal(r.status,200);assert.equal(r.body.committed,true);assert.equal(h.calls.length,1);assert.equal(h.calls[0].name,'travel_credit_sandbox_coins');assert.equal(h.calls[0].args.apple_product,product);
});
test('production uses production ledger',async()=>{const h=harness({environment:'Production'});const r=await h.request({action:'deliver',signed_transaction:'e30.eyJ0ZXN0Ijp0cnVlfQ.c2ln',bundle_id:'com.lulu.tourtravel',environment:'Production'});assert.equal(r.body.committed,true);assert.equal(h.calls[0].name,'travel_credit_apple_coins');});
for(const options of [{verificationFails:true},{owner:'00000000-0000-4000-8000-000000000002'},{bundle:'com.other.app'},{environment:'Xcode'},{product:'unknownproductxx'}])test(`invalid transaction cannot credit ${JSON.stringify(options)}`,async()=>{const h=harness(options);const r=await h.request({action:'deliver',signed_transaction:'e30.eyJ0ZXN0Ijp0cnVlfQ.c2ln',bundle_id:'com.lulu.tourtravel',environment:'Sandbox'});assert.notEqual(r.body.committed,true);assert.equal(h.calls.length,0);});
test('failed persistence cannot report success',async()=>{const h=harness({ledgerFails:true});const r=await h.request({action:'deliver',signed_transaction:'e30.eyJ0ZXN0Ijp0cnVlfQ.c2ln',bundle_id:'com.lulu.tourtravel',environment:'Sandbox'});assert.notEqual(r.body.committed,true);});
