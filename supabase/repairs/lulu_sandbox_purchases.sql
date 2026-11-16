-- Separate Apple sandbox balances and entitlements from the production economy.
create table public.sandbox_coin_deliveries (
    bundle_id text not null check (bundle_id = 'com.lulu.tourtravel'),
    transaction_id text not null,
    owner_id uuid references auth.users(id) on delete set null,
    product_id text not null references public.coin_products(product_id),
    delivered_at timestamptz not null default now(),
    primary key (bundle_id, transaction_id)
);
create table public.sandbox_wallet_activity (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    bundle_id text not null check (bundle_id = 'com.lulu.tourtravel'),
    amount integer not null,
    description text not null,
    created_at timestamptz not null default now()
);
create index sandbox_wallet_owner_idx on public.sandbox_wallet_activity(owner_id, bundle_id);
create table public.sandbox_guide_unlocks (
    owner_id uuid not null references auth.users(id) on delete cascade,
    bundle_id text not null check (bundle_id = 'com.lulu.tourtravel'),
    guide_id uuid not null references public.guides(id) on delete cascade,
    price_coins integer not null check (price_coins > 0),
    unlocked_at timestamptz not null default now(),
    primary key (owner_id, bundle_id, guide_id)
);
alter table public.sandbox_coin_deliveries enable row level security;
alter table public.sandbox_wallet_activity enable row level security;
alter table public.sandbox_guide_unlocks enable row level security;
revoke all on public.sandbox_coin_deliveries, public.sandbox_wallet_activity, public.sandbox_guide_unlocks from public, anon, authenticated;

create function public.travel_credit_sandbox_coins(viewer uuid, apple_transaction text, apple_product text, apple_bundle text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    package_coins integer;
    delivery public.sandbox_coin_deliveries%rowtype;
begin
    if viewer is null or apple_bundle is distinct from 'com.lulu.tourtravel'
       or apple_transaction is null or apple_transaction !~ '^[0-9]{1,32}$' then
        raise exception 'Invalid Apple transaction';
    end if;
    select coins into package_coins from public.coin_products where product_id = apple_product;
    if not found then raise exception 'Unknown Apple product'; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(viewer::text, 1122));
    insert into public.sandbox_coin_deliveries(bundle_id, transaction_id, owner_id, product_id)
    values (apple_bundle, apple_transaction, viewer, apple_product)
    on conflict (bundle_id, transaction_id) do nothing;
    if found then
        insert into public.sandbox_wallet_activity(owner_id, bundle_id, amount, description)
        values(viewer, apple_bundle, package_coins, 'Apple sandbox coin purchase');
    else
        select * into delivery from public.sandbox_coin_deliveries
        where bundle_id = apple_bundle and transaction_id = apple_transaction;
        if delivery.owner_id is distinct from viewer or delivery.product_id <> apple_product then
            raise exception 'Apple transaction belongs to a different purchase';
        end if;
    end if;
    return jsonb_build_object('committed', true);
end;
$$;
revoke all on function public.travel_credit_sandbox_coins(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.travel_credit_sandbox_coins(uuid,text,text,text) to service_role;

-- The authenticated wrapper never accepts a viewer identifier from the client.
create function public.travel_sandbox_coin_state(apple_bundle text)
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

create function public.travel_unlock_sandbox_guide(target_guide uuid, expected_price integer, apple_bundle text)
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
