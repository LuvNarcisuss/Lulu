-- Run on a disposable PostgreSQL database with the Lulu migrations applied.
begin;

insert into auth.users (id) values
    ('44444444-4444-4444-8444-444444444444'),
    ('77777777-7777-4777-8777-777777777777');
insert into public.profiles (id, user_id, data) values
    ('44444444-4444-4444-8444-444444444444', '44444444-4444-4444-8444-444444444444', '{"display_name":"Account deletion fixture"}'),
    ('77777777-7777-4777-8777-777777777777', '77777777-7777-4777-8777-777777777777', '{"display_name":"Retained account fixture"}');
insert into public.places (id, data) values
    ('55555555-5555-4555-8555-555555555551', '{}');
insert into public.clips (id, place_id, publisher_id, data) values
    ('55555555-5555-4555-8555-555555555552', '55555555-5555-4555-8555-555555555551', '44444444-4444-4444-8444-444444444444',
     '{"title":"A published film","author":"Account deletion fixture","owner_id":"44444444-4444-4444-8444-444444444444","video_path":"uploads/44444444-4444-4444-8444-444444444444/video/a.mp4","cover_path":"uploads/44444444-4444-4444-8444-444444444444/cover/a.jpg"}');
insert into public.guides (id, place_id, data) values
    ('55555555-5555-4555-8555-555555555553', '55555555-5555-4555-8555-555555555551', '{"title":"A published guide","intro":"Preserved travel notes"}'),
    ('55555555-5555-4555-8555-555555555554', '55555555-5555-4555-8555-555555555551', '{"title":"A pending guide","intro":"Private submission"}');
insert into public.guide_offers (guide_id, place_id, author_id, title, preview, price_coins, status) values
    ('55555555-5555-4555-8555-555555555553', '55555555-5555-4555-8555-555555555551', '44444444-4444-4444-8444-444444444444', 'A published guide', 'Published notes', 180, 'published'),
    ('55555555-5555-4555-8555-555555555554', '55555555-5555-4555-8555-555555555551', '44444444-4444-4444-8444-444444444444', 'A pending guide', 'Private notes', 0, 'pending');
insert into public.guide_unlocks (owner_id, guide_id, price_coins) values
    ('77777777-7777-4777-8777-777777777777', '55555555-5555-4555-8555-555555555553', 180);
insert into public.saved_clips (owner_id, target_id) values
    ('77777777-7777-4777-8777-777777777777', '55555555-5555-4555-8555-555555555552');
insert into public.journeys (owner_id, data) values
    ('44444444-4444-4444-8444-444444444444', '{}'), ('77777777-7777-4777-8777-777777777777', '{}');
insert into public.submissions (owner_id, data) values
    ('44444444-4444-4444-8444-444444444444', '{"status":"pending"}');
insert into public.conversations (id, direct_key, data) values
    ('55555555-5555-4555-8555-555555555555', '44444444-4444-4444-8444-444444444444:77777777-7777-4777-8777-777777777777', '{"is_group":false}');
insert into public.conversation_members (conversation_id, user_id) values
    ('55555555-5555-4555-8555-555555555555', '44444444-4444-4444-8444-444444444444'),
    ('55555555-5555-4555-8555-555555555555', '77777777-7777-4777-8777-777777777777');
insert into public.messages (id, conversation_id, sender_id, data) values
    ('55555555-5555-4555-8555-555555555556', '55555555-5555-4555-8555-555555555555', '44444444-4444-4444-8444-444444444444', '{"body":"Remove my message"}'),
    ('55555555-5555-4555-8555-555555555557', '55555555-5555-4555-8555-555555555555', '77777777-7777-4777-8777-777777777777', '{"body":"Keep the other member’s message"}');
insert into storage.objects (bucket_id, name) values
    ('uploads', '44444444-4444-4444-8444-444444444444/video/a.mp4'),
    ('uploads', '44444444-4444-4444-8444-444444444444/cover/a.jpg'),
    ('uploads', '44444444-4444-4444-8444-444444444444/avatar/a.jpg'),
    ('uploads', '77777777-7777-4777-8777-777777777777/avatar/b.jpg');

do $$
begin
    if has_function_privilege('anon', 'public.travel_account_media(uuid,boolean)', 'execute')
       or has_function_privilege('authenticated', 'public.travel_account_media(uuid,boolean)', 'execute')
       or not has_function_privilege('service_role', 'public.travel_account_media(uuid,boolean)', 'execute') then
        raise exception 'Unexpected account media privileges';
    end if;
end;
$$;

set local role service_role;
do $$
declare plan jsonb;
begin
    plan := public.travel_account_media('44444444-4444-4444-8444-444444444444', false);
    if jsonb_array_length(plan) <> 2 or plan::text like '%avatar%' then
        raise exception 'Retention plan should contain only the published cover and video';
    end if;
    begin
        perform public.travel_account_media('44444444-4444-4444-8444-444444444444', true);
        raise exception 'Expected a missing retained copy error';
    exception when raise_exception then
        if sqlerrm <> 'Retained community media is incomplete' then raise; end if;
    end;
end;
$$;
reset role;

-- Model the successful Storage API copies with fixture metadata only.
insert into storage.objects (bucket_id, name)
select 'uploads', destination from private.account_clip_media('44444444-4444-4444-8444-444444444444');
insert into storage.objects (bucket_id, name) values ('uploads', 'community/unreferenced.jpg');

set local role service_role;
do $$
begin
    if public.travel_account_media('44444444-4444-4444-8444-444444444444', false) <> '[]' then
        raise exception 'Retry must reuse staged copies';
    end if;
    perform public.travel_account_media('44444444-4444-4444-8444-444444444444', true);
    perform public.travel_account_media('44444444-4444-4444-8444-444444444444', true);
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
do $$
begin
    begin
        insert into storage.objects (bucket_id, name) values ('uploads', '44444444-4444-4444-8444-444444444444/avatar/late.jpg');
        raise exception 'The pending deletion must stop new uploads';
    exception when insufficient_privilege then null;
    end;
end;
$$;
reset role;

do $$
begin
    begin
        delete from auth.users where id = '44444444-4444-4444-8444-444444444444';
        raise exception 'Expected a private storage cleanup error';
    exception when raise_exception then
        if sqlerrm <> 'Finish account media cleanup before deleting the identity' then raise; end if;
    end;
end;
$$;

-- Model deletion through the Storage API before the Auth admin call.
delete from storage.objects where bucket_id = 'uploads' and name like '44444444-4444-4444-8444-444444444444/%';
set local role supabase_auth_admin;
delete from auth.users where id = '44444444-4444-4444-8444-444444444444';
reset role;

do $$
begin
    if exists (select 1 from public.profiles where id = '44444444-4444-4444-8444-444444444444')
       or exists (select 1 from public.journeys where owner_id = '44444444-4444-4444-8444-444444444444')
       or exists (select 1 from public.submissions where owner_id = '44444444-4444-4444-8444-444444444444')
       or exists (select 1 from public.messages where id = '55555555-5555-4555-8555-555555555556')
       or exists (select 1 from public.guides where id = '55555555-5555-4555-8555-555555555554') then
        raise exception 'The deleted account left personal rows';
    end if;
    if not exists (select 1 from public.clips where id = '55555555-5555-4555-8555-555555555552'
                   and publisher_id is null and data->>'retained_community' = 'true'
                   and not data ? 'author' and not data ? 'owner_id'
                   and data->>'video_path' like 'uploads/community/%'
                   and data->>'cover_path' like 'uploads/community/%')
       or not exists (select 1 from public.guide_offers where guide_id = '55555555-5555-4555-8555-555555555553'
                      and author_id is null and status = 'published' and price_coins = 180 and retained_community)
       or not exists (select 1 from public.guide_unlocks where owner_id = '77777777-7777-4777-8777-777777777777')
       or not exists (select 1 from public.saved_clips where owner_id = '77777777-7777-4777-8777-777777777777')
       or not exists (select 1 from public.journeys where owner_id = '77777777-7777-4777-8777-777777777777')
       or not exists (select 1 from public.messages where id = '55555555-5555-4555-8555-555555555557')
       or not exists (select 1 from public.conversations where id = '55555555-5555-4555-8555-555555555555' and direct_key is null)
       or not exists (select 1 from storage.objects where name = '77777777-7777-4777-8777-777777777777/avatar/b.jpg') then
        raise exception 'Published content or a different account was changed incorrectly';
    end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '77777777-7777-4777-8777-777777777777', true);
do $$
begin
    if (select count(*) from storage.objects where name like 'community/%') <> 2 then
        raise exception 'Only referenced retained media must be readable';
    end if;
    if not exists (select 1 from public.guides where id = '55555555-5555-4555-8555-555555555553') then
        raise exception 'The other account must keep its paid guide entitlement';
    end if;
end;
$$;
select set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
do $$
begin
    begin
        insert into storage.objects (bucket_id, name) values ('uploads', '44444444-4444-4444-8444-444444444444/avatar/stale.jpg');
        raise exception 'A stale token must not upload after account deletion';
    exception when insufficient_privilege then null;
    end;
end;
$$;
reset role;

rollback;
