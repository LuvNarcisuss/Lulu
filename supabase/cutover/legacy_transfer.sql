-- Install only in the original Lulu project. The app sends its old session only to this issuer.
create table private.lulu_company_tickets (
    member_id uuid primary key references auth.users(id) on delete cascade,
    destination_id uuid not null,
    digest bytea not null unique,
    expires_at timestamptz not null
);
alter table private.lulu_company_tickets enable row level security;
revoke all on private.lulu_company_tickets from public, anon, authenticated;

create function public.travel_issue_company_ticket(destination_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    member uuid := auth.uid();
    ticket text := encode(extensions.gen_random_bytes(32), 'hex');
begin
    if member is null or destination_id is null or not exists (
        select 1 from auth.users u where u.id = member and u.is_anonymous and u.deleted_at is null
    ) then raise exception 'A saved guest session is required'; end if;
    insert into private.lulu_company_tickets values (
        member, destination_id, sha256(convert_to(ticket, 'UTF8')), now() + interval '5 minutes'
    ) on conflict (member_id) do update set destination_id = excluded.destination_id,
        digest = excluded.digest, expires_at = excluded.expires_at;
    return jsonb_build_object('ticket', ticket);
end $$;
revoke all on function public.travel_issue_company_ticket(uuid) from public, anon, authenticated;
grant execute on function public.travel_issue_company_ticket(uuid) to authenticated;

-- Only the random one-use ticket and the destination account it names can reveal a handoff.
create function public.travel_redeem_company_ticket(destination_id uuid, ticket text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare member uuid;
begin
    if ticket ~ '^[a-f0-9]{64}$' then
        delete from private.lulu_company_tickets t
        where t.destination_id = travel_redeem_company_ticket.destination_id and t.expires_at > now()
          and t.digest = sha256(convert_to(ticket, 'UTF8'))
        returning t.member_id into member;
    end if;
    return jsonb_build_object('account_id', member);
end $$;
revoke all on function public.travel_redeem_company_ticket(uuid,text) from public, anon, authenticated;
grant execute on function public.travel_redeem_company_ticket(uuid,text) to anon;
