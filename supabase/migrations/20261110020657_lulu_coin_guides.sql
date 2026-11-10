create table public.coin_products (
    product_id text primary key check (product_id ~ '^[a-z]{16}$'),
    coins integer not null check (coins > 0)
);
alter table public.coin_products enable row level security;
revoke all on public.coin_products from public, anon, authenticated;

insert into public.coin_products (product_id, coins) values
    ('iltpkpefqtjskxel', 400),
    ('eweerqrczkwsjyjn', 800),
    ('bfktecvbuyjzwxtp', 2450),
    ('zsadvhodvgamjqqp', 5150),
    ('qtqrufubdpyvzjzs', 10800),
    ('ipcijraguygtcpsa', 17000),
    ('azjrhiwubtjsrbzh', 29400),
    ('qjcdfljcmzajynnd', 42700),
    ('rzeethasxinmprew', 63700);

create table public.coin_apple_deliveries (
    transaction_id text primary key,
    owner_id uuid references auth.users(id) on delete set null,
    product_id text not null references public.coin_products(product_id),
    delivered_at timestamptz not null default now()
);
alter table public.coin_apple_deliveries enable row level security;
revoke all on public.coin_apple_deliveries from public, anon, authenticated;

create table public.guide_offers (
    guide_id uuid primary key references public.guides(id) on delete cascade,
    place_id uuid not null references public.places(id) on delete cascade,
    author_id uuid references auth.users(id) on delete cascade,
    title text not null check (char_length(title) between 1 and 100),
    preview text not null check (char_length(preview) between 1 and 500),
    price_coins integer not null check (price_coins between 0 and 10000),
    status text not null check (status in ('pending', 'published', 'rejected')),
    created_at timestamptz not null default now()
);
create index guide_offers_place_idx on public.guide_offers (place_id);
create index guide_offers_author_idx on public.guide_offers (author_id);
alter table public.guide_offers enable row level security;
revoke all on public.guide_offers from public, anon, authenticated;
grant select on public.guide_offers to authenticated;
create policy read_visible_guide_offers on public.guide_offers for select to authenticated
using (
    author_id = (select auth.uid()) or
    (status = 'published' and (author_id is null or not private.blocked((select auth.uid()), author_id)))
);

create table public.guide_unlocks (
    owner_id uuid not null references auth.users(id) on delete cascade,
    guide_id uuid not null references public.guides(id) on delete cascade,
    price_coins integer not null check (price_coins > 0),
    unlocked_at timestamptz not null default now(),
    primary key (owner_id, guide_id)
);
create index guide_unlocks_guide_idx on public.guide_unlocks (guide_id);
alter table public.guide_unlocks enable row level security;
revoke all on public.guide_unlocks from public, anon, authenticated;
grant select on public.guide_unlocks to authenticated;
create policy read_own_guide_unlocks on public.guide_unlocks for select to authenticated
using (owner_id = (select auth.uid()));

insert into public.guide_offers (guide_id, place_id, title, preview, price_coins, status)
select g.id, g.place_id, g.data->>'title', left(g.data->>'intro', 500),
       case p.data->>'name'
           when 'Colosseum and Ancient Rome' then 180
           when 'Swiss Alps' then 260
           when 'Santorini Caldera Villages' then 140
           when 'Moraine Lake, Banff' then 220
           else 0
       end,
       'published'
from public.guides g join public.places p on p.id = g.place_id;

alter policy read_guides on public.guides using (
    exists (
        select 1 from public.guide_offers o
        where o.guide_id = guides.id
          and (
              o.author_id = (select auth.uid())
              or (o.status = 'published' and (
                  o.price_coins = 0 or exists (
                      select 1 from public.guide_unlocks u
                      where u.guide_id = guides.id and u.owner_id = (select auth.uid())
                  )
              ))
          )
    )
);

create function public.travel_coin_state() returns jsonb
language sql stable security invoker set search_path = '' as $$
    select jsonb_build_object(
        'balance', coalesce((
            select sum((w.data->>'amount')::bigint)
            from public.wallet_activity w
            where w.owner_id = (select auth.uid()) and w.data->>'currency' = 'coins'
        ), 0),
        'activity', coalesce((
            select jsonb_agg(w.data || jsonb_build_object('created_at', w.created_at) order by w.created_at desc)
            from (
                select data, created_at from public.wallet_activity
                where owner_id = (select auth.uid()) and data->>'currency' = 'coins'
                order by created_at desc limit 100
            ) w
        ), '[]'::jsonb),
        'offers', coalesce((
            select jsonb_agg(
                to_jsonb(o) || jsonb_build_object('unlocked', exists(
                    select 1 from public.guide_unlocks u
                    where u.guide_id = o.guide_id and u.owner_id = (select auth.uid())
                )) order by o.created_at, o.guide_id
            )
            from public.guide_offers o
        ), '[]'::jsonb)
    );
$$;

create function public.travel_unlock_guide(target_guide uuid, expected_price integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    viewer uuid := auth.uid();
    listing public.guide_offers%rowtype;
    coins bigint;
begin
    if viewer is null then raise exception 'Authentication required'; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(viewer::text, 1121));
    select * into listing from public.guide_offers where guide_id = target_guide for share;
    if not found or listing.status <> 'published'
        or (listing.author_id is not null and private.blocked(viewer, listing.author_id)) then
        raise exception 'Guide unavailable';
    end if;
    if listing.author_id = viewer or listing.price_coins = 0
        or exists (select 1 from public.guide_unlocks where owner_id = viewer and guide_id = target_guide) then
        return jsonb_build_object('committed', true);
    end if;
    if expected_price is distinct from listing.price_coins then raise exception 'Guide price changed. Refresh before unlocking.'; end if;
    select coalesce(sum((w.data->>'amount')::bigint), 0) into coins
    from public.wallet_activity w where w.owner_id = viewer and w.data->>'currency' = 'coins';
    if coins < listing.price_coins then raise exception 'Not enough coins'; end if;
    insert into public.guide_unlocks (owner_id, guide_id, price_coins)
    values (viewer, target_guide, listing.price_coins);
    insert into public.wallet_activity (owner_id, target_id, data)
    values (viewer, target_guide, jsonb_build_object(
        'currency', 'coins', 'kind', 'guide_unlock', 'description', listing.title, 'amount', -listing.price_coins
    ));
    return jsonb_build_object('committed', true);
end;
$$;

create function public.travel_submit_guide(
    guide_key uuid, destination uuid, guide_title text, guide_preview text, guide_body text, coin_price integer
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    author uuid := auth.uid();
begin
    if author is null then raise exception 'Authentication required'; end if;
    if guide_key is null or destination is null or coin_price is null or coin_price not between 0 and 10000
        or guide_title is null or char_length(btrim(guide_title)) not between 3 and 100
        or guide_preview is null or char_length(btrim(guide_preview)) not between 10 and 500
        or guide_body is null or char_length(btrim(guide_body)) not between 40 and 8000
        or not exists (select 1 from public.places where id = destination) then
        raise exception 'Check the destination, text lengths and coin price';
    end if;
    insert into public.guides (id, place_id, data)
    values (guide_key, destination, jsonb_build_object(
        'title', btrim(guide_title), 'intro', btrim(guide_preview),
        'sections', jsonb_build_array(jsonb_build_object('title', 'Travel notes', 'body', btrim(guide_body)))
    )) on conflict (id) do nothing;
    if found then
        insert into public.guide_offers (guide_id, place_id, author_id, title, preview, price_coins, status)
        values (guide_key, destination, author, btrim(guide_title), btrim(guide_preview), coin_price, 'pending');
    elsif not exists (select 1 from public.guide_offers where guide_id = guide_key and author_id = author) then
        raise exception 'Guide unavailable';
    end if;
    return jsonb_build_object('committed', true);
end;
$$;

create function public.travel_price_guide(target_guide uuid, coin_price integer) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    if coin_price is null or coin_price not between 0 and 10000 then raise exception 'Invalid coin price'; end if;
    update public.guide_offers set price_coins = coin_price
    where guide_id = target_guide and author_id = auth.uid();
    if not found then raise exception 'Guide unavailable'; end if;
    return jsonb_build_object('committed', true);
end;
$$;

create function public.travel_report_guide(target_id uuid, reason text, details text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    viewer uuid := auth.uid();
    listing public.guide_offers%rowtype;
begin
    if viewer is null then raise exception 'Authentication required'; end if;
    select * into listing from public.guide_offers where guide_id = target_id;
    if not found or listing.status <> 'published' or listing.author_id = viewer
        or (listing.author_id is not null and private.blocked(viewer, listing.author_id)) then
        raise exception 'Guide unavailable';
    end if;
    if reason is null or char_length(btrim(reason)) not between 1 and 80
        or details is null or char_length(btrim(details)) > 500 then raise exception 'Invalid report'; end if;
    insert into public.reports (owner_id, target_id, data)
    values (viewer, target_id, jsonb_build_object('user_id', viewer, 'target_kind', 'guide',
        'target_id', target_id, 'reason', btrim(reason), 'details', btrim(details)));
    return jsonb_build_object('committed', true);
end;
$$;

create function public.travel_credit_apple_coins(viewer uuid, apple_transaction text, apple_product text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
    package_coins integer;
    delivery public.coin_apple_deliveries%rowtype;
begin
    if viewer is null or apple_transaction is null or apple_transaction !~ '^[0-9]{1,32}$' then
        raise exception 'Invalid Apple transaction';
    end if;
    select coins into package_coins from public.coin_products where product_id = apple_product;
    if not found then raise exception 'Unknown Apple product'; end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(viewer::text, 1121));
    insert into public.coin_apple_deliveries (transaction_id, owner_id, product_id)
    values (apple_transaction, viewer, apple_product) on conflict (transaction_id) do nothing;
    if found then
        insert into public.wallet_activity (owner_id, data)
        values (viewer, jsonb_build_object('currency', 'coins', 'kind', 'apple_purchase',
            'description', 'Apple coin purchase', 'amount', package_coins));
    else
        select * into delivery from public.coin_apple_deliveries where transaction_id = apple_transaction;
        if delivery.owner_id is distinct from viewer or delivery.product_id <> apple_product then
            raise exception 'Apple transaction belongs to a different purchase';
        end if;
    end if;
    return jsonb_build_object('committed', true);
end;
$$;

revoke all on function public.travel_coin_state(), public.travel_unlock_guide(uuid, integer),
    public.travel_submit_guide(uuid, uuid, text, text, text, integer),
    public.travel_price_guide(uuid, integer), public.travel_report_guide(uuid, text, text)
from public, anon, authenticated;
grant execute on function public.travel_coin_state(), public.travel_unlock_guide(uuid, integer),
    public.travel_submit_guide(uuid, uuid, text, text, text, integer),
    public.travel_price_guide(uuid, integer), public.travel_report_guide(uuid, text, text)
to authenticated;
revoke all on function public.travel_credit_apple_coins(uuid, text, text) from public, anon, authenticated;
grant execute on function public.travel_credit_apple_coins(uuid, text, text) to service_role;
