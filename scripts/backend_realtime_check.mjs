import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
const {projectURL: base, publishableKey: key} = JSON.parse(await readFile('LuluApp/Resources/BackendConfig.json', 'utf8'));
const users=JSON.parse(await readFile('/tmp/lulu-company-verification-sessions.json','utf8'));
const previous=JSON.parse(await readFile('docs/backend/api-verification.json','utf8'));
if (previous.project !== new URL(base).hostname.split('.')[0]) throw new Error('Run the company backend check before using its verification sessions.');
async function api(path,body,user,method='POST'){
 const response=await fetch(base+path,{method,headers:{apikey:key,'Content-Type':'application/json',...(user?{Authorization:'Bearer '+user.access_token}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});const data=await response.json();if(!response.ok)throw Object.assign(new Error(data.message||data.error||'Request failed'),{status:response.status});return data;
}
const rpc=(name,body,u)=>api('/rest/v1/rpc/'+name,body,u);
const action=(name,payload,u)=>rpc('travel_action',{action:name,payload},u);
function socket(user,c){
 const ws=new WebSocket(base.replace('https:', 'wss:')+'/realtime/v1/websocket?apikey='+key+'&vsn=1.0.0');const events=[];const listeners=[];const topic='realtime:verification-'+randomUUID();
 const joined=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Realtime join timed out')),18000);ws.addEventListener('open',()=>ws.send(JSON.stringify({topic,event:'phx_join',payload:{config:{broadcast:{self:false},presence:{key:''},postgres_changes:[{event:'INSERT',schema:'public',table:'messages',filter:'conversation_id=eq.'+c}]},access_token:user.access_token},ref:'1'})));
 ws.addEventListener('message',event=>{const m=JSON.parse(event.data);if(m.event==='phx_reply'&&m.ref==='1'){clearTimeout(timer);if(m.payload.status!=='ok')reject(new Error('Realtime join rejected'));}if(m.event==='system'&&m.payload.status==='ok'){clearTimeout(timer);resolve();}if(m.event==='postgres_changes'){events.push(m.payload);for(const listener of listeners)listener(m.payload);}});ws.addEventListener('error',()=>{clearTimeout(timer);reject(new Error('Realtime connection failed'));});});
 return {ws,joined,events,wait(id){const predicate=p=>p.data?.record?.id===id;const found=events.find(predicate);if(found)return Promise.resolve(found);return new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Realtime message timed out')),12000);listeners.push(p=>{if(predicate(p)){clearTimeout(timer);resolve(p);}});});},close(){ws.close();}};
}
let result={project:previous.project,checks:[],status:'failed'};const sockets=[];
try{
 const good=await api('/functions/v1/travel-entry',{},users[0]);if(good.code!==0||JSON.stringify(good.data)!=='{}')throw new Error('Entry bootstrap shape');
 for(const user of [undefined,{access_token:'invalid-token'}]){let denied=false;try{await api('/functions/v1/travel-entry',{},user)}catch(e){denied=e.status===401}if(!denied)throw new Error('Entry auth rejection');}result.checks.push('deployed travel-entry valid session and anonymous/bad-token rejection');
 const c=previous.directConversation;const a=socket(users[0],c),b=socket(users[1],c),outsider=socket(users[2],c);sockets.push(a,b,outsider);await Promise.all(sockets.map(s=>s.joined));
 const message=(body)=>({id:randomUUID(),conversation_id:c,body,attachment_path:null,attachment_type:null,reply_to:null});
 let m=message('Realtime A to B');await action('chat.send',m,users[0]);await b.wait(m.id);
 m=message('Realtime B to A');await action('chat.send',m,users[1]);await a.wait(m.id);result.checks.push('two participant sockets receive persisted messages in both directions');
 b.close();let gap=message('Persisted during disconnect');await action('chat.send',gap,users[0]);const reconnected=socket(users[1],c);sockets.push(reconnected);await reconnected.joined;
 const snapshot=await rpc('travel_snapshot',{},users[1]);if(!snapshot.messages.some(x=>x.id===gap.id))throw new Error('Reconnect history missing');
 m=message('After reconnect');await action('chat.send',m,users[0]);await reconnected.wait(m.id);
 if(outsider.events.length)throw new Error('Nonmember received private realtime event');result.checks.push('disconnect history catchup, resubscribed live event, and nonmember receives no message event');result.status='passed';
}catch(e){result.error={message:e.message,status:e.status};}finally{for(const s of sockets)s.close();}
await writeFile('docs/backend/realtime-verification.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
