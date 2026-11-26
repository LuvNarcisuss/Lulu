-- Install only in the company project after importing Lulu's existing identities and data.
create table private.lulu_account_links (
    auth_user_id uuid primary key references auth.users(id) on delete cascade,
    account_id uuid not null references auth.users(id) on delete cascade,
    check (account_id <> auth_user_id)
);
alter table private.lulu_account_links enable row level security;
revoke all on private.lulu_account_links from public, anon, authenticated;

create function private.lulu_actor() returns uuid
language sql stable security definer set search_path = '' as $$
    select coalesce((select l.account_id from private.lulu_account_links l where l.auth_user_id=auth.uid()), auth.uid());
$$;
revoke all on function private.lulu_actor() from public, anon, authenticated;
grant execute on function private.lulu_actor() to authenticated;

create function public.travel_account_identity() returns jsonb
language sql stable security invoker set search_path = '' as $$
    select jsonb_build_object('account_id', private.lulu_actor());
$$;
revoke all on function public.travel_account_identity() from public, anon, authenticated;
grant execute on function public.travel_account_identity() to authenticated;

create function public.travel_bind_company_account(session_user_id uuid, imported_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare linked uuid;
begin
    perform pg_advisory_xact_lock(hashtextextended(session_user_id::text, 4270));
    select account_id into linked from private.lulu_account_links where auth_user_id = session_user_id;
    if linked = imported_id then return jsonb_build_object('account_id', linked); end if;
    if linked is not null or session_user_id = imported_id
       or not exists (select 1 from auth.users where id=session_user_id and is_anonymous and deleted_at is null)
       or not exists (select 1 from public.profiles where id=imported_id and user_id=imported_id)
       or exists (select 1 from public.profiles where user_id=session_user_id)
    then raise exception 'The saved account could not be linked'; end if;
    insert into private.lulu_account_links values (session_user_id, imported_id);
    return jsonb_build_object('account_id', imported_id);
end $$;
revoke all on function public.travel_bind_company_account(uuid,uuid) from public, anon, authenticated;
grant execute on function public.travel_bind_company_account(uuid,uuid) to service_role;

-- Keep the complete installed function and policy bodies, including their grants and predicates.
-- Only the authenticated principal changes. Auth and Storage platform objects stay platform-owned.
do $$
declare entry record;
begin
    for entry in
        select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where (n.nspname='public' and p.proname in (
            'travel_action','travel_coin_state','travel_guide_visibility','travel_price_guide',
            'travel_report_guide','travel_sandbox_coin_state','travel_snapshot','travel_submit_guide',
            'travel_unlock_guide','travel_unlock_sandbox_guide'
        )) or (n.nspname='private' and p.proname in ('can_view_guide_author','content_statistics','profile_statistics'))
    loop
        execute replace(pg_get_functiondef(entry.oid), 'auth.uid()', 'private.lulu_actor()');
    end loop;
    for entry in select * from pg_policies
        where (schemaname='public' or (schemaname='storage' and tablename='objects'
               and policyname in ('read_upload','upload_own')))
          and concat(qual, with_check) like '%auth.uid()%'
    loop
        execute format('alter policy %I on %I.%I', entry.policyname,entry.schemaname,entry.tablename)
            || coalesce(' using (' || replace(entry.qual,'auth.uid()','private.lulu_actor()') || ')','')
            || coalesce(' with check (' || replace(entry.with_check,'auth.uid()','private.lulu_actor()') || ')','');
    end loop;
end $$;

create or replace function public.travel_bootstrap() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare member uuid;
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 4270));
    member := private.lulu_actor();
    insert into public.profiles(id,user_id,data) values(member,member,
        jsonb_build_object('display_name','Traveler','bio','','avatar_path','','is_editorial',false,
                           'source_url','','consent_version','')) on conflict(id) do nothing;
    return jsonb_build_object('code',0,'message','ok','data','{}'::jsonb,'account_id',member);
end $$;
