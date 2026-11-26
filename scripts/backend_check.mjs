import { readFile, writeFile, chmod } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
const {projectURL: url, publishableKey: key} = JSON.parse(await readFile('LuluApp/Resources/BackendConfig.json', 'utf8'));
const sessionPath='/tmp/lulu-company-verification-sessions.json';
let users=[];
try { users=JSON.parse(await readFile(sessionPath,'utf8')); } catch {}
async function api(path,body,user,method='POST') {
 const response=await fetch(url+path,{method,headers:{apikey:key,'Content-Type':'application/json',...(user?{Authorization:'Bearer '+user.access_token}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});
 const text=await response.text();let value;try{value=JSON.parse(text)}catch{value={message:text}};
 if(!response.ok) throw Object.assign(new Error(value.message||value.error_description||value.error||'Request failed'),{status:response.status,value});
 return value;
}
const check=(ok,message)=>{if(!ok)throw new Error(message);};
for(let i=users.length;i<3;i++){
 const session=await api('/auth/v1/signup',{}); users.push(session);await writeFile(sessionPath,JSON.stringify(users));await chmod(sessionPath,0o600);
}
const rpc=(name,body,u)=>api('/rest/v1/rpc/'+name,body,u);
const action=(name,payload,u)=>rpc('travel_action',{action:name,payload},u);
const ids=users.map(x=>x.user.id);let report={project:new URL(url).hostname.split('.')[0],users:ids,checks:[],cleanupPending:true};
try {
 let rejected=false;try{await rpc('travel_bootstrap',{})}catch(e){rejected=e.status===401||e.status===403}check(rejected,'Raw anonymous bootstrap must reject');report.checks.push('raw anonymous RPC denied');
 for(const [i,u]of users.entries()){
  const b=await rpc('travel_bootstrap',{},u);check(b.code===0&&JSON.stringify(b.data)==='{}','Bootstrap contract');
  await action('profile.update',{display_name:'Backend Verification '+String(i+1),bio:'Isolated deployment verification account.',consent_version:'2026-11-03-v1'},u);
 }
 const snap=await rpc('travel_snapshot',{},users[0]);check(snap.balance===0,'Zero wallet');check(snap.journeys.length===0&&snap.messages.length===0&&snap.likes.length===0,'Empty private state');report.checks.push('real guest Auth, bootstrap, profile, zero wallet, empty personal state');
 console.log(JSON.stringify({status:'initial checks passed',counts:Object.fromEntries(['clips','places','guides','profiles'].map(k=>[k,snap[k].length]))}));
 const j=randomUUID();const journey={id:j,title:'Verification Journey',start_date:'2026-12-01',end_date:'2026-12-02',currency:'EUR',budget:20,days:[],checklist:[],notes:'Private persistence check'};
 await action('journey.save',journey,users[0]);check((await rpc('travel_snapshot',{},users[0])).journeys.some(x=>x.id===j),'Journey readback');check(!(await rpc('travel_snapshot',{},users[1])).journeys.some(x=>x.id===j),'Journey owner isolation');
 rejected=false;try{await action('journey.save',journey,users[1])}catch{rejected=true}check(rejected,'Cross-user write rejected');
 await action('journey.delete',{journey_id:j},users[0]);report.checks.push('journey save/readback/delete and cross-user read/write isolation');
 const pair=await action('chat.direct',{profile_id:ids[1]},users[0]);const pairAgain=await action('chat.direct',{profile_id:ids[0]},users[1]);check(pair.conversation_id===pairAgain.conversation_id,'Canonical direct pair');
 const c=pair.conversation_id;const msg={id:randomUUID(),conversation_id:c,body:'Verification greeting',attachment_path:null,attachment_type:null,reply_to:null};
 await action('chat.send',msg,users[0]);await action('chat.send',msg,users[0]);
 check((await rpc('travel_snapshot',{},users[1])).messages.filter(x=>x.id===msg.id).length===1,'Message participant readback and dedup');
 rejected=false;try{await action('chat.send',{...msg,id:randomUUID()},users[0])}catch{rejected=true}check(rejected,'Nonmutual greeting restriction');
 rejected=false;try{await action('chat.send',{...msg,id:randomUUID()},users[2])}catch{rejected=true}check(rejected,'Nonmember send denied');
 check(!(await rpc('travel_snapshot',{},users[2])).messages.some(x=>x.id===msg.id),'Nonmember read isolation');
 await action('relationship.follow',{profile_id:ids[1],enabled:true},users[0]);await action('relationship.follow',{profile_id:ids[0],enabled:true},users[1]);
 await action('chat.send',{...msg,id:randomUUID(),body:'Mutual follow message'},users[0]);
 await action('chat.preferences',{conversation_id:c,pinned:true,draft:'Unsent draft'},users[0]);await action('chat.preferences',{conversation_id:c,muted:true},users[0]);
 const pref=(await rpc('travel_snapshot',{},users[0])).chat_preferences.find(x=>x.conversation_id===c);check(pref.pinned&&pref.muted&&pref.draft==='Unsent draft','Partial preferences preserve omitted keys');
 await action('safety.block',{profile_id:ids[1],enabled:true},users[0]);rejected=false;try{await action('chat.send',{...msg,id:randomUUID()},users[1])}catch{rejected=true}check(rejected,'Blocked messaging denied');await action('safety.block',{profile_id:ids[1],enabled:false},users[0]);
 report.directConversation=c;report.checks.push('canonical DM, message persistence/dedup, nonmutual greeting, mutual follow, partial preferences, member isolation, server block');
 const group=await action('chat.group',{title:'Verification group',member_ids:[ids[1],ids[2]]},users[0]);report.groupConversation=group.conversation_id;
 await action('chat.send',{...msg,id:randomUUID(),conversation_id:group.conversation_id,body:'Group message'},users[2]);report.checks.push('real group membership and message persistence');
 if(snap.clips.length){const clip=snap.clips[0].id;await action('clip.like',{clip_id:clip,enabled:true},users[0]);await action('clip.save',{clip_id:clip,enabled:true},users[0]);const comment=await action('comment.add',{clip_id:clip,body:'Verification comment',parent_id:null},users[0]);await action('comment.delete',{comment_id:comment.id},users[0]);await action('clip.like',{clip_id:clip,enabled:false},users[0]);await action('clip.save',{clip_id:clip,enabled:false},users[0]);report.checks.push('clip like/save/comment create/delete');}
 report.status='passed';
} catch(e){report.status='failed';report.error={message:e.message,status:e.status};}
await writeFile('docs/backend/api-verification.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
