-- Exercise the company identity mapping and retention triggers with transaction-local fixtures.
begin;
do $$
declare
    login_id uuid := gen_random_uuid();
    member_id uuid := gen_random_uuid();
    reader_id uuid := gen_random_uuid();
    place_id uuid := gen_random_uuid();
    film_id uuid := gen_random_uuid();
    published_id uuid := gen_random_uuid();
    draft_id uuid := gen_random_uuid();
begin
    insert into auth.users(id, is_anonymous) values (login_id, false), (member_id, true), (reader_id, false);
    insert into private.lulu_account_links values (login_id, member_id);
    insert into public.profiles(id, user_id, data) values (member_id, member_id, '{}'), (reader_id, reader_id, '{}');
    insert into public.places(id, data) values (place_id, '{}');
    insert into public.clips(id, place_id, publisher_id, data) values (film_id, place_id, member_id, '{"author":"QA"}');
    insert into public.guides(id, place_id, data) values (published_id, place_id, '{}'), (draft_id, place_id, '{}');
    insert into public.guide_offers(guide_id, place_id, author_id, title, preview, price_coins, status)
    values (published_id, place_id, member_id, 'Guide', 'Published guide preview', 180, 'published'),
           (draft_id, place_id, member_id, 'Draft', 'Private draft preview', 0, 'pending');
    insert into public.guide_unlocks(owner_id, guide_id, price_coins) values (reader_id, published_id, 180);
    insert into public.journeys(owner_id, data) values (member_id, '{}'), (reader_id, '{}');
    perform set_config('request.jwt.claim.sub', login_id::text, true);
    if not private.can_upload_for_account() then raise exception 'Linked member cannot upload before deletion'; end if;
    if public.travel_begin_self_deletion(login_id) <> member_id
       or public.travel_begin_self_deletion(login_id) <> member_id then raise exception 'Incorrect deletion owner'; end if;
    if private.can_upload_for_account() then raise exception 'A pending deletion still allows uploads'; end if;
    perform public.travel_account_media(member_id, false);
    perform public.travel_account_media(member_id, true);
    delete from auth.users where id = login_id;
    if exists (select 1 from auth.users where id in (login_id, member_id))
       or exists (select 1 from public.profiles where id = member_id)
       or exists (select 1 from public.journeys where owner_id = member_id)
       or exists (select 1 from public.guides where id = draft_id)
       or exists (select 1 from private.account_deletion_requests where user_id = member_id)
       or private.can_upload_for_account() then raise exception 'Private account state survived'; end if;
    if not exists (select 1 from public.clips where id = film_id and publisher_id is null and not (data ? 'author'))
       or not exists (select 1 from public.guide_offers where guide_id = published_id and retained_community and author_id is null)
       or not exists (select 1 from public.guide_unlocks where owner_id = reader_id and guide_id = published_id)
       or not exists (select 1 from public.journeys where owner_id = reader_id)
       then raise exception 'Community or reader data was lost'; end if;
    perform set_config('request.jwt.claim.sub', reader_id::text, true);
    begin
        perform public.travel_unlock_sandbox_guide(published_id, 180, 'com.lulu.tourtravel');
        raise exception 'A retained member guide was offered for sandbox coins';
    exception when raise_exception then
        if sqlerrm <> 'Member guides cannot be purchased with sandbox coins' then raise; end if;
    end;
end $$;
rollback;
