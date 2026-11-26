import { readFile,writeFile } from 'node:fs/promises';
import {createHash} from 'node:crypto';
const {projectURL} = JSON.parse(await readFile('LuluApp/Resources/BackendConfig.json', 'utf8'));
const base = projectURL + '/storage/v1/object/public/';
const manifest=JSON.parse(await readFile('Assets/media-manifest.json','utf8'));
const result=[];let i=0;
async function worker(){while(i<manifest.files.length){const f=manifest.files[i++];try{const r=await fetch(base+f.path,{signal:AbortSignal.timeout(45000)});const b=Buffer.from(await r.arrayBuffer());const hash=createHash('sha256').update(b).digest('hex');result.push({path:f.path,status:r.status,bytes:b.length,sha256:hash,contentType:r.headers.get('content-type'),verified:r.ok&&hash===f.sha256&&b.length===f.bytes});}catch(e){result.push({path:f.path,verified:false,error:e.message});}}}
await Promise.all(Array.from({length:4},worker));
await writeFile('docs/backend/media-verification.json',JSON.stringify({project:new URL(projectURL).hostname.split('.')[0],verified:result.every(x=>x.verified),files:result},null,2)+'\n');
const policies=[];
for(const name of ['terms','privacy']){const path='legal/'+name+'.pdf';const r=await fetch(base+path);const bytes=Buffer.from(await r.arrayBuffer());const hash=createHash('sha256').update(bytes).digest('hex');const local=createHash('sha256').update(await readFile('docs/backend/legal/'+name+'.pdf')).digest('hex');policies.push({name,url:base+path,status:r.status,contentType:r.headers.get('content-type'),bytes:bytes.length,sha256:hash,verified:r.ok&&bytes.subarray(0,5).toString()==='%PDF-'&&hash===local});await writeFile('/tmp/travel-public-'+name+'.pdf',bytes);}
await writeFile('docs/backend/legal/public-verification.json',JSON.stringify(policies,null,2)+'\n');
console.log(JSON.stringify({mediaVerified:result.filter(x=>x.verified).length,expected:manifest.files.length,failed:result.filter(x=>!x.verified),policies}));
