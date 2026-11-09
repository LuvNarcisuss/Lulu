
create schema if not exists private;
revoke all on schema private from public;
create table public.profiles (id uuid primary key, user_id uuid unique references auth.users(id) on delete cascade, data jsonb not null check(jsonb_typeof(data)='object'), created_at timestamptz not null default now());
create table public.places (id uuid primary key, data jsonb not null check(jsonb_typeof(data)='object'));
create table public.clips (id uuid primary key, place_id uuid references public.places(id), publisher_id uuid references public.profiles(id), data jsonb not null check(jsonb_typeof(data)='object'));
create table public.guides (id uuid primary key, place_id uuid references public.places(id), data jsonb not null check(jsonb_typeof(data)='object'));
create table public.conversations (id uuid primary key default gen_random_uuid(), direct_key text unique, data jsonb not null, updated_at timestamptz not null default now());
create table public.conversation_members (conversation_id uuid references public.conversations(id) on delete cascade, user_id uuid references auth.users(id) on delete cascade, primary key(conversation_id,user_id));
create table public.messages (id uuid primary key, conversation_id uuid not null references public.conversations(id) on delete cascade, sender_id uuid not null references auth.users(id) on delete cascade, data jsonb not null, created_at timestamptz not null default now());
create index messages_conversation_created on public.messages(conversation_id,created_at);
create index members_user on public.conversation_members(user_id,conversation_id);
create function private.member(c uuid, u uuid) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.conversation_members where conversation_id=c and user_id=u) $$;
create table public.likes (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, target_id uuid references public.clips(id) on delete cascade, data jsonb not null default '{}', created_at timestamptz not null default now(), unique(owner_id,target_id));
create index likes_owner on public.likes(owner_id);
create table public.saved_clips (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, target_id uuid references public.clips(id) on delete cascade, data jsonb not null default '{}', created_at timestamptz not null default now(), unique(owner_id,target_id));
create index saved_clips_owner on public.saved_clips(owner_id);
create table public.saved_places (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, target_id uuid references public.places(id) on delete cascade, data jsonb not null default '{}', created_at timestamptz not null default now(), unique(owner_id,target_id));
create index saved_places_owner on public.saved_places(owner_id);
create table public.follows (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, target_id uuid references public.profiles(id) on delete cascade, data jsonb not null default '{}', created_at timestamptz not null default now(), unique(owner_id,target_id));
create index follows_owner on public.follows(owner_id);
create table public.blocks (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, target_id uuid references public.profiles(id) on delete cascade, data jsonb not null default '{}', created_at timestamptz not null default now(), unique(owner_id,target_id));
create index blocks_owner on public.blocks(owner_id);
create table public.reports (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, target_id uuid, data jsonb not null default '{}', created_at timestamptz not null default now());
create index reports_owner on public.reports(owner_id);
create table public.journeys (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, target_id uuid, data jsonb not null default '{}', created_at timestamptz not null default now());
create index journeys_owner on public.journeys(owner_id);
create table public.chat_preferences (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, target_id uuid references public.conversations(id) on delete cascade, data jsonb not null default '{}', created_at timestamptz not null default now(), unique(owner_id,target_id));
create index chat_preferences_owner on public.chat_preferences(owner_id);
create table public.submissions (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, target_id uuid references public.places(id), data jsonb not null default '{}', created_at timestamptz not null default now());
create index submissions_owner on public.submissions(owner_id);
create table public.wallet_activity (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, target_id uuid, data jsonb not null default '{}', created_at timestamptz not null default now());
create index wallet_activity_owner on public.wallet_activity(owner_id);

create function private.blocked(a uuid,b uuid) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.blocks where (owner_id=a and target_id=b) or (owner_id=b and target_id=a)) $$;
create table public.comments (id uuid primary key default gen_random_uuid(), clip_id uuid not null references public.clips(id) on delete cascade, user_id uuid not null references auth.users(id) on delete cascade, parent_id uuid references public.comments(id) on delete set null, body text not null check(length(body) between 1 and 2000), created_at timestamptz not null default now());
create index comments_clip_created on public.comments(clip_id,created_at);
create index comments_user on public.comments(user_id);
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
alter table public.places enable row level security;
revoke all on public.places from anon, authenticated;
grant select on public.places to authenticated;
alter table public.clips enable row level security;
revoke all on public.clips from anon, authenticated;
grant select on public.clips to authenticated;
alter table public.guides enable row level security;
revoke all on public.guides from anon, authenticated;
grant select on public.guides to authenticated;
alter table public.conversations enable row level security;
revoke all on public.conversations from anon, authenticated;
grant select on public.conversations to authenticated;
alter table public.conversation_members enable row level security;
revoke all on public.conversation_members from anon, authenticated;
grant select on public.conversation_members to authenticated;
alter table public.messages enable row level security;
revoke all on public.messages from anon, authenticated;
grant select on public.messages to authenticated;
alter table public.comments enable row level security;
revoke all on public.comments from anon, authenticated;
grant select on public.comments to authenticated;
alter table public.likes enable row level security;
revoke all on public.likes from anon, authenticated;
grant select on public.likes to authenticated;
alter table public.saved_clips enable row level security;
revoke all on public.saved_clips from anon, authenticated;
grant select on public.saved_clips to authenticated;
alter table public.saved_places enable row level security;
revoke all on public.saved_places from anon, authenticated;
grant select on public.saved_places to authenticated;
alter table public.follows enable row level security;
revoke all on public.follows from anon, authenticated;
grant select on public.follows to authenticated;
alter table public.blocks enable row level security;
revoke all on public.blocks from anon, authenticated;
grant select on public.blocks to authenticated;
alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;
grant select on public.reports to authenticated;
alter table public.journeys enable row level security;
revoke all on public.journeys from anon, authenticated;
grant select on public.journeys to authenticated;
alter table public.chat_preferences enable row level security;
revoke all on public.chat_preferences from anon, authenticated;
grant select on public.chat_preferences to authenticated;
alter table public.submissions enable row level security;
revoke all on public.submissions from anon, authenticated;
grant select on public.submissions to authenticated;
alter table public.wallet_activity enable row level security;
revoke all on public.wallet_activity from anon, authenticated;
grant select on public.wallet_activity to authenticated;
create policy read_profiles on public.profiles for select to authenticated using (true);
create policy read_places on public.places for select to authenticated using (true);
create policy read_clips on public.clips for select to authenticated using (true);
create policy read_guides on public.guides for select to authenticated using (true);
create policy read_comments on public.comments for select to authenticated using (true);
create policy read_own_likes on public.likes for select to authenticated using (owner_id=(select auth.uid()));
create policy read_own_saved_clips on public.saved_clips for select to authenticated using (owner_id=(select auth.uid()));
create policy read_own_saved_places on public.saved_places for select to authenticated using (owner_id=(select auth.uid()));
create policy read_follows on public.follows for select to authenticated using (true);
create policy read_own_blocks on public.blocks for select to authenticated using (owner_id=(select auth.uid()));
create policy read_own_reports on public.reports for select to authenticated using (owner_id=(select auth.uid()));
create policy read_own_journeys on public.journeys for select to authenticated using (owner_id=(select auth.uid()));
create policy read_own_chat_preferences on public.chat_preferences for select to authenticated using (owner_id=(select auth.uid()));
create policy read_own_submissions on public.submissions for select to authenticated using (owner_id=(select auth.uid()));
create policy read_own_wallet_activity on public.wallet_activity for select to authenticated using (owner_id=(select auth.uid()));

create policy read_conversations on public.conversations for select to authenticated using(private.member(id,(select auth.uid())));
create policy read_members on public.conversation_members for select to authenticated using(private.member(conversation_id,(select auth.uid())));
create policy read_messages on public.messages for select to authenticated using(private.member(conversation_id,(select auth.uid())));
grant usage on schema private to authenticated;
grant execute on function private.member(uuid,uuid) to authenticated;
revoke all on function private.blocked(uuid,uuid) from public;
create function public.travel_bootstrap() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); begin
if u is null then raise exception 'Authentication required'; end if;
insert into public.profiles(id,user_id,data) values(u,u,jsonb_build_object('display_name','Traveler','bio','','avatar_path','','is_editorial',false,'source_url','','consent_version','')) on conflict(id) do nothing;
return '{"code":0,"message":"ok","data":{}}'::jsonb;
end $$;
create function public.travel_snapshot() returns jsonb language plpgsql security invoker set search_path='' as $$
declare r jsonb:='{}'; t text; v jsonb; begin
if auth.uid() is null then raise exception 'Authentication required'; end if;
foreach t in array array['clips','places','guides','profiles','likes','saved_clips','saved_places','follows','blocks','reports','journeys','chat_preferences','submissions','wallet_activity'] loop
execute format('select coalesce(jsonb_agg(x),''[]''::jsonb) from (select data || (to_jsonb(z)-''data''-''direct_key'') as x from public.%I z order by id limit 2000) q',t) into v;
r:=r || jsonb_build_object(t,v);
end loop;
select coalesce(jsonb_agg(to_jsonb(c)),'[]') into v from (select * from public.comments order by created_at desc limit 2000)c;
r:=r||jsonb_build_object('comments',v);
select coalesce(jsonb_agg(data||jsonb_build_object('id',c.id,'updated_at',c.updated_at,'member_ids',(select jsonb_agg(user_id) from public.conversation_members m where m.conversation_id=c.id),'last_message',coalesce((select data->>'body' from public.messages where conversation_id=c.id order by created_at desc limit 1),''),'unread_count',(select count(*) from public.messages m where m.conversation_id=c.id and sender_id<>auth.uid() and created_at>coalesce((select (data->>'last_read_at')::timestamptz from public.chat_preferences p where p.owner_id=auth.uid() and p.target_id=c.id),'1970-01-01'::timestamptz)))),'[]') into v from public.conversations c;
r:=r||jsonb_build_object('conversations',v);
select coalesce(jsonb_agg(data||jsonb_build_object('id',id,'conversation_id',conversation_id,'sender_id',sender_id,'created_at',created_at)),'[]') into v from (select * from public.messages order by created_at desc limit 5000)m;
return r||jsonb_build_object('messages',v,'profile',(select data||jsonb_build_object('id',id) from public.profiles where id=auth.uid()),'balance',0);
end $$;
create function private.require_text(p jsonb,k text,minlen int,maxlen int) returns text language plpgsql immutable set search_path='' as $$
declare v text:=btrim(p->>k); begin if v is null or length(v)<minlen or length(v)>maxlen then raise exception 'Invalid %',k; end if; return v; end $$;
create function private.owned_media(path text,u uuid) returns boolean language sql stable security definer set search_path='' as $$ select path is null or path='' or (path like 'uploads/'||u::text||'/%' and exists(select 1 from storage.objects where bucket_id='uploads' and name=substr(path,9))) $$;
create function public.travel_action(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); p jsonb:=payload; k uuid; c uuid; other uuid; t text; v jsonb; members uuid[]; mk text; enabled boolean; begin
if u is null then raise exception 'Authentication required'; end if;
if jsonb_typeof(p)<>'object' or octet_length(p::text)>300000 then raise exception 'Invalid payload'; end if;
case action
when 'profile.update' then
v:='{}';
if p ? 'display_name' then v:=v||jsonb_build_object('display_name',private.require_text(p,'display_name',1,60)); end if;
if p ? 'bio' then v:=v||jsonb_build_object('bio',private.require_text(p,'bio',0,500)); end if;
if p ? 'avatar_path' then if not private.owned_media(p->>'avatar_path',u) then raise exception 'Invalid avatar'; end if; v:=v||jsonb_build_object('avatar_path',p->'avatar_path'); end if;
if p ? 'consent_version' then v:=v||jsonb_build_object('consent_version',private.require_text(p,'consent_version',1,40)); end if;
update public.profiles set data=data||v where id=u;
when 'clip.like','clip.save','place.save','relationship.follow','safety.block' then
if jsonb_typeof(p->'enabled')<>'boolean' then raise exception 'Invalid enabled'; end if;
enabled:=(p->>'enabled')::boolean;
t:=case action when 'clip.like' then 'likes' when 'clip.save' then 'saved_clips' when 'place.save' then 'saved_places' when 'relationship.follow' then 'follows' else 'blocks' end;
k:=coalesce(p->>'clip_id',p->>'place_id',p->>'profile_id')::uuid;
if action in ('relationship.follow','safety.block') then
if k=u or not exists(select 1 from public.profiles where id=k) then raise exception 'Invalid profile'; end if;
end if;
if enabled then
v:=case action when 'clip.like' then jsonb_build_object('clip_id',k,'user_id',u) when 'clip.save' then jsonb_build_object('clip_id',k,'user_id',u) when 'place.save' then jsonb_build_object('place_id',k,'user_id',u) when 'relationship.follow' then jsonb_build_object('follower_id',u,'following_id',k) else jsonb_build_object('blocker_id',u,'blocked_id',k) end;
execute format('insert into public.%I(owner_id,target_id,data) values($1,$2,$3) on conflict(owner_id,target_id) do nothing',t) using u,k,v;
else execute format('delete from public.%I where owner_id=$1 and target_id=$2',t) using u,k; end if;
when 'comment.add' then
k:=(p->>'clip_id')::uuid; c:=nullif(p->>'parent_id','')::uuid;
if c is not null and not exists(select 1 from public.comments where id=c and clip_id=k) then raise exception 'Invalid reply'; end if;
insert into public.comments(clip_id,user_id,parent_id,body) values(k,u,c,private.require_text(p,'body',1,2000)) returning id into k;
when 'comment.delete' then delete from public.comments where id=(p->>'comment_id')::uuid and user_id=u; if not found then raise exception 'Comment unavailable'; end if;
when 'safety.report' then
 t:=private.require_text(p,'target_kind',1,30); k:=(p->>'target_id')::uuid;
if t not in ('clip','profile','comment','message','place') then raise exception 'Invalid report target'; end if;
if (t='message' and not exists(select 1 from public.messages where id=k and private.member(conversation_id,u))) or (t='profile' and not exists(select 1 from public.profiles where id=k)) or (t='clip' and not exists(select 1 from public.clips where id=k)) or (t='place' and not exists(select 1 from public.places where id=k)) or (t='comment' and not exists(select 1 from public.comments where id=k)) then raise exception 'Target unavailable'; end if;
insert into public.reports(owner_id,target_id,data) values(u,k,jsonb_build_object('user_id',u,'target_kind',t,'target_id',k,'reason',private.require_text(p,'reason',1,80),'details',private.require_text(p,'details',0,2000))) returning id into k;
when 'safety.unreport' then delete from public.reports where id=(p->>'report_id')::uuid and owner_id=u;
when 'journey.save' then
k:=(p->>'id')::uuid;
perform private.require_text(p,'title',1,100);
if not (p ?& array['id','title','start_date','end_date','currency','budget','days','checklist','notes']) or jsonb_typeof(p->'days')<>'array' or jsonb_typeof(p->'checklist')<>'array' or jsonb_array_length(p->'days')>180 or jsonb_array_length(p->'checklist')>500 or coalesce((p->>'budget')::numeric,-1)<0 or length(p->>'notes')>20000 or (p->>'start_date')::date>(p->>'end_date')::date or (p->>'currency')!~'^[A-Z]{3}$' then raise exception 'Invalid journey'; end if;
if exists(select 1 from public.journeys where id=k and owner_id<>u) then raise exception 'Journey unavailable'; end if;
for v in select value from jsonb_array_elements(p->'days') loop
if jsonb_typeof(v->'stops')<>'array' or jsonb_array_length(v->'stops')>100 then raise exception 'Invalid day'; end if;
perform (v->>'id')::uuid; perform (v->>'date')::date;
if exists(select 1 from jsonb_array_elements(v->'stops') s where not exists(select 1 from public.places where id=(s->>'place_id')::uuid)) then raise exception 'Invalid place'; end if;
end loop;
insert into public.journeys(id,owner_id,data) values(k,u,jsonb_build_object('title',p->'title','start_date',p->'start_date','end_date',p->'end_date','currency',p->'currency','budget',p->'budget','days',p->'days','checklist',p->'checklist','notes',p->'notes','owner_id',u,'updated_at',now())) on conflict(id) do update set data=excluded.data where public.journeys.owner_id=u;
when 'journey.delete' then delete from public.journeys where id=(p->>'journey_id')::uuid and owner_id=u; if not found then raise exception 'Journey unavailable'; end if;
when 'chat.direct','chat.group' then
if action='chat.direct' then members:=array[u,(p->>'profile_id')::uuid];
else
perform private.require_text(p,'title',1,100); select array_agg(distinct x::uuid) into members from jsonb_array_elements_text(p->'member_ids') x; members:=array_append(members,u);
if cardinality(members)<3 or cardinality(members)>30 then raise exception 'Choose two to twenty-nine other members'; end if;
end if;
select array_agg(distinct x order by x) into members from unnest(members)x;
if cardinality(members)<2 then raise exception 'Choose another member'; end if;
foreach other in array members loop
if not exists(select 1 from public.profiles where id=other and user_id is not null) or private.blocked(u,other) then raise exception 'Member unavailable'; end if;
end loop;
if action='chat.direct' then
mk:=array_to_string(members,':');
insert into public.conversations(direct_key,data) values(mk,jsonb_build_object('title','','is_group',false)) on conflict(direct_key) do update set direct_key=excluded.direct_key returning id into c;
else insert into public.conversations(data) values(jsonb_build_object('title',p->>'title','is_group',true)) returning id into c; end if;
insert into public.conversation_members(conversation_id,user_id) select c,unnest(members) on conflict do nothing;
return jsonb_build_object('conversation_id',c);
when 'chat.send' then
c:=(p->>'conversation_id')::uuid; k:=(p->>'id')::uuid;
if not private.member(c,u) then raise exception 'Conversation unavailable'; end if;
perform 1 from public.conversations where id=c for update;
if exists(select 1 from public.conversation_members where conversation_id=c and private.blocked(u,user_id)) then raise exception 'Messaging unavailable'; end if;
if exists(select 1 from public.messages where id=k and (sender_id<>u or conversation_id<>c or data<>(p-'id'-'sender_id'-'created_at'))) then raise exception 'Message identifier conflict'; end if;
if exists(select 1 from public.messages where id=k) then return jsonb_build_object('id',k,'committed',true); end if;
if exists(select 1 from public.conversations where id=c and coalesce((data->>'is_group')::boolean,false)=false) then
select user_id into other from public.conversation_members where conversation_id=c and user_id<>u limit 1;
if not (exists(select 1 from public.follows where owner_id=u and target_id=other) and exists(select 1 from public.follows where owner_id=other and target_id=u)) and exists(select 1 from public.messages where conversation_id=c and sender_id=u) then raise exception 'You have already sent your greeting. Follow each other to keep chatting.'; end if;
end if;
perform private.require_text(p,'body',0,4000);
if btrim(coalesce(p->>'body',''))='' and coalesce(p->>'attachment_path','')='' then raise exception 'Message is empty'; end if;
if not private.owned_media(p->>'attachment_path',u) then raise exception 'Invalid attachment'; end if;
if coalesce(p->>'attachment_path','')<>'' and coalesce(p->>'attachment_type','') not in ('image','image/jpeg','image/png','image/heic') then raise exception 'Invalid attachment type'; end if;
if p->>'reply_to' is not null and not exists(select 1 from public.messages where id=(p->>'reply_to')::uuid and conversation_id=c) then raise exception 'Invalid reply'; end if;
insert into public.messages(id,conversation_id,sender_id,data) values(k,c,u,p-'id'-'sender_id'-'created_at') on conflict(id) do nothing;
update public.conversations set updated_at=now() where id=c;
when 'chat.preferences' then
c:=(p->>'conversation_id')::uuid;
if not private.member(c,u) then raise exception 'Conversation unavailable'; end if;
v:='{}'; foreach t in array array['pinned','muted','archived'] loop if p ? t then if jsonb_typeof(p->t)<>'boolean' then raise exception 'Invalid preference'; end if; v:=v||jsonb_build_object(t,p->t); end if; end loop;
if p ? 'draft' then v:=v||jsonb_build_object('draft',private.require_text(p,'draft',0,4000)); end if;
if p ? 'last_read_at' then v:=v||jsonb_build_object('last_read_at',least((p->>'last_read_at')::timestamptz,now())); end if;
insert into public.chat_preferences(owner_id,target_id,data) values(u,c,jsonb_build_object('conversation_id',c,'user_id',u,'pinned',false,'muted',false,'archived',false,'draft','')||v) on conflict(owner_id,target_id) do update set data=public.chat_preferences.data||v;
when 'submission.create' then
k:=(p->>'id')::uuid; perform private.require_text(p,'title',1,120); perform private.require_text(p,'caption',0,2000);
if coalesce(p->>'video_path','')='' or coalesce(p->>'cover_path','')='' or not private.owned_media(p->>'video_path',u) or not private.owned_media(p->>'cover_path',u) then raise exception 'Upload both video and cover first'; end if;
if exists(select 1 from public.submissions where id=k and owner_id<>u) then raise exception 'Submission unavailable'; end if;
insert into public.submissions(id,owner_id,target_id,data) values(k,u,(p->>'place_id')::uuid,(p-'owner_id'-'status'-'created_at')||jsonb_build_object('owner_id',u,'status','pending')) on conflict(id) do nothing;
when 'submission.delete' then delete from public.submissions where id=(p->>'submission_id')::uuid and owner_id=u; if not found then raise exception 'Submission unavailable'; end if;
else raise exception 'Unsupported action'; end case;
return jsonb_build_object('id',k,'committed',true);
end $$;
revoke all on function public.travel_bootstrap(), public.travel_snapshot(), public.travel_action(text,jsonb) from public;
grant execute on function public.travel_bootstrap(),public.travel_snapshot(),public.travel_action(text,jsonb) to authenticated;
revoke all on all functions in schema private from public;
grant execute on function private.member(uuid,uuid) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('catalog','catalog',true,104857600,array['image/jpeg','image/png','video/mp4']),('legal','legal',true,10485760,array['application/pdf']),('uploads','uploads',false,104857600,array['image/jpeg','image/png','image/heic','video/mp4','video/quicktime']);
create policy upload_own on storage.objects for insert to authenticated with check(bucket_id='uploads' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy read_upload on storage.objects for select to authenticated using(bucket_id='uploads' and ((storage.foldername(name))[1]=(select auth.uid())::text or exists(select 1 from public.messages m where m.data->>'attachment_path'='uploads/'||name and private.member(m.conversation_id,(select auth.uid()))) or exists(select 1 from public.profiles p where p.data->>'avatar_path'='uploads/'||name)));
alter publication supabase_realtime add table public.messages, public.conversation_members, public.conversations;
