-- Apply in the company project together with the account deletion retention migration.
alter table private.account_deletion_requests add column requested_by uuid;
alter table private.account_deletion_requests enable row level security;

create function public.travel_begin_self_deletion(login_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare member_id uuid;
begin
    perform 1 from auth.users where id = login_id and not is_anonymous and deleted_at is null for update;
    if not found then raise exception 'A registered login is required'; end if;
    select account_id into member_id from private.lulu_account_links where auth_user_id = login_id;
    if not found then
        member_id := login_id;
    else
        perform 1 from auth.users where id = member_id and is_anonymous and deleted_at is null for update;
        if not found then raise exception 'The imported guest identity could not be verified'; end if;
    end if;
    insert into private.account_deletion_requests as pending(user_id, requested_by)
    values (member_id, login_id)
    on conflict (user_id) do update set requested_by = excluded.requested_by
    where pending.requested_by is null or pending.requested_by = excluded.requested_by;
    if not found then raise exception 'The account already has a pending request'; end if;
    return member_id;
end $$;
revoke all on function public.travel_begin_self_deletion(uuid) from public, anon, authenticated;
grant execute on function public.travel_begin_self_deletion(uuid) to service_role;

create or replace function private.can_upload_for_account() returns boolean
language plpgsql security definer set search_path = '' as $$
declare member_id uuid := private.lulu_actor();
begin
    perform 1 from auth.users where id = member_id for key share;
    if not found then return false; end if;
    return not exists (select 1 from private.account_deletion_requests where user_id = member_id);
end $$;
alter policy upload_own on storage.objects with check (
    bucket_id = 'uploads'
    and (storage.foldername(name))[1] = (select private.lulu_actor())::text
    and (select private.can_upload_for_account())
);

-- Auth deletes the verified login. Its imported guest and private rows are removed in the same transaction.
create function private.delete_linked_guest_with_login() returns trigger
language plpgsql security definer set search_path = '' as $$
declare guest_id uuid;
begin
    select user_id into guest_id from private.account_deletion_requests
    where requested_by = old.id and user_id <> old.id;
    if found then
        delete from auth.users u using private.lulu_account_links l
        where l.auth_user_id = old.id and l.account_id = guest_id and u.id = guest_id and u.is_anonymous;
        if not found then raise exception 'The imported guest identity could not be verified'; end if;
    end if;
    return old;
end $$;
revoke all on function private.delete_linked_guest_with_login() from public, anon, authenticated;
create trigger delete_linked_guest_with_login before delete on auth.users
for each row execute function private.delete_linked_guest_with_login();

-- Published member guides retain their original purchase rules after their author is removed.
do $$
declare definition text;
begin
    definition := pg_get_functiondef('public.travel_unlock_sandbox_guide(uuid,integer,text)'::regprocedure);
    if strpos(definition, 'if listing.author_id is not null then') = 0 then raise exception 'Unexpected sandbox entitlement definition'; end if;
    execute replace(definition, 'if listing.author_id is not null then', 'if listing.author_id is not null or listing.retained_community then');
    definition := pg_get_functiondef('public.travel_sandbox_coin_state(text)'::regprocedure);
    if strpos(definition, 'and o.author_id is null)') = 0 then raise exception 'Unexpected sandbox guide definition'; end if;
    execute replace(definition, 'and o.author_id is null)', 'and o.author_id is null and not o.retained_community)');
end $$;
