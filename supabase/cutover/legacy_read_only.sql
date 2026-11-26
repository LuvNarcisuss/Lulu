-- Retire the app-facing writers on the original project. Keep existing Auth refreshes and transfer tickets.
do $$
declare entry record;
begin
    for entry in select schemaname, tablename from pg_tables
        where schemaname='public' or (schemaname='private' and tablename='editorial_display_baselines')
        order by schemaname, tablename
    loop
        execute format('lock table %I.%I in share row exclusive mode',entry.schemaname,entry.tablename);
        execute format('revoke insert, update, delete, truncate on %I.%I from public, anon, authenticated, service_role',
            entry.schemaname,entry.tablename);
    end loop;
    for entry in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.proname in (
            'travel_bootstrap','travel_action','travel_guide_visibility','travel_price_guide','travel_submit_guide',
            'travel_report_guide','travel_unlock_guide','travel_unlock_sandbox_guide',
            'travel_credit_apple_coins','travel_credit_sandbox_coins'
        )
    loop
        execute format('revoke execute on function %s from public, anon, authenticated, service_role',entry.oid::regprocedure);
    end loop;
end $$;
revoke update (is_hidden) on public.guide_visibility from public, anon, authenticated, service_role;
alter policy upload_own on storage.objects with check (false);

-- The retired release must not create stranded anonymous identities after the final import.
-- This affects new identity creation only. Existing users and sessions remain available to Auth.
create function private.lulu_retire_signup() returns trigger
language plpgsql set search_path = '' as $$
begin
    raise exception 'Please update Lulu to start a new account.';
end $$;
revoke all on function private.lulu_retire_signup() from public, anon, authenticated;
create trigger lulu_retire_signup before insert on auth.users
    for each row execute function private.lulu_retire_signup();
