-- Restrict sandbox entitlements and content to owner-authorized editorial guides.
create or replace function public.travel_sandbox_coin_state(apple_bundle text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
    viewer uuid := auth.uid();
begin
    if viewer is null or apple_bundle is distinct from 'com.lulu.tourtravel' then raise exception 'Invalid wallet request'; end if;
    return jsonb_build_object(
        'balance', (select coalesce(sum(amount::bigint), 0) from public.sandbox_wallet_activity
                    where owner_id = viewer and bundle_id = apple_bundle),
        'activity', coalesce((select jsonb_agg(to_jsonb(w) order by w.created_at desc) from
                    (select amount, description, created_at from public.sandbox_wallet_activity
                     where owner_id = viewer and bundle_id = apple_bundle order by created_at desc limit 100) w), '[]'::jsonb),
        'offers', coalesce((select jsonb_agg(to_jsonb(o) || jsonb_build_object('unlocked', exists (
                     select 1 from public.sandbox_guide_unlocks u where u.owner_id = viewer
                     and u.bundle_id = apple_bundle and u.guide_id = o.guide_id)))
                     from public.guide_offers o where o.author_id = viewer or
                     (o.status = 'published' and (o.author_id is null or not private.blocked(viewer, o.author_id)))), '[]'::jsonb),
        'guides', coalesce((select jsonb_agg(g.data || jsonb_build_object('id', g.id, 'place_id', g.place_id))
                    from public.guides g join public.guide_offers o on o.guide_id = g.id
                    join public.sandbox_guide_unlocks u on u.guide_id = g.id
                    where u.owner_id = viewer and u.bundle_id = apple_bundle and o.status = 'published'
                    and o.author_id is null), '[]'::jsonb)
    );
end;
$$;

create or replace function public.travel_unlock_sandbox_guide(target_guide uuid, expected_price integer, apple_bundle text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    viewer uuid := auth.uid();
    listing public.guide_offers%rowtype;
    coins bigint;
begin
    if viewer is null or apple_bundle is distinct from 'com.lulu.tourtravel' then raise exception 'Invalid wallet request'; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(viewer::text, 1122));
    select * into listing from public.guide_offers where guide_id = target_guide for share;
    if not found or listing.status <> 'published' then raise exception 'Guide unavailable'; end if;
    if listing.author_id is not null then raise exception 'Member guides cannot be purchased with sandbox coins'; end if;
    if listing.author_id = viewer or listing.price_coins = 0 or exists (
       select 1 from public.sandbox_guide_unlocks where owner_id = viewer and bundle_id = apple_bundle and guide_id = target_guide) then
        return jsonb_build_object('committed', true);
    end if;
    if expected_price is distinct from listing.price_coins then raise exception 'Guide price changed. Refresh before unlocking.'; end if;
    select coalesce(sum(amount::bigint),0) into coins from public.sandbox_wallet_activity where owner_id = viewer and bundle_id = apple_bundle;
    if coins < listing.price_coins then raise exception 'Not enough coins'; end if;
    insert into public.sandbox_guide_unlocks(owner_id,bundle_id,guide_id,price_coins)
    values(viewer,apple_bundle,target_guide,listing.price_coins);
    insert into public.sandbox_wallet_activity(owner_id,bundle_id,amount,description)
    values(viewer,apple_bundle,-listing.price_coins,listing.title);
    return jsonb_build_object('committed',true);
end;
$$;
revoke all on function public.travel_sandbox_coin_state(text), public.travel_unlock_sandbox_guide(uuid,integer,text) from public, anon, authenticated;
grant execute on function public.travel_sandbox_coin_state(text), public.travel_unlock_sandbox_guide(uuid,integer,text) to authenticated;
