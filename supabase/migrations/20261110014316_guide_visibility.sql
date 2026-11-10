create table public.guide_visibility (
    owner_id uuid not null references auth.users(id) on delete cascade,
    place_id uuid not null references public.places(id) on delete cascade,
    is_hidden boolean not null,
    primary key (owner_id, place_id)
);
create index guide_visibility_place_id_idx on public.guide_visibility(place_id);

alter table public.guide_visibility enable row level security;
revoke all on public.guide_visibility from public, anon, authenticated;
grant select, insert on public.guide_visibility to authenticated;
grant update (is_hidden) on public.guide_visibility to authenticated;

create policy read_own_guide_visibility on public.guide_visibility
    for select to authenticated using (owner_id = (select auth.uid()));
create policy insert_own_guide_visibility on public.guide_visibility
    for insert to authenticated with check (owner_id = (select auth.uid()));
create policy update_own_guide_visibility on public.guide_visibility
    for update to authenticated using (owner_id = (select auth.uid()))
    with check (owner_id = (select auth.uid()));

create function public.travel_guide_visibility(place_id uuid default null, enabled boolean default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
    viewer uuid := auth.uid();
    target_place uuid := place_id;
begin
    if viewer is null then raise exception 'Authentication required'; end if;
    if (target_place is null) <> (enabled is null) then
        raise exception 'Invalid guide visibility request';
    end if;
    if target_place is not null then
        if not exists (select 1 from public.places p where p.id = target_place) then
            raise exception 'Guide unavailable';
        end if;
        insert into public.guide_visibility (owner_id, place_id, is_hidden)
        values (viewer, target_place, enabled)
        on conflict on constraint guide_visibility_pkey do update set is_hidden = excluded.is_hidden;
    end if;
    return jsonb_build_object('hidden_place_ids', (
        select coalesce(jsonb_agg(g.place_id order by g.place_id), '[]'::jsonb)
        from public.guide_visibility g
        where g.owner_id = viewer and g.is_hidden
    ));
end;
$$;

revoke all on function public.travel_guide_visibility(uuid, boolean) from public, anon, authenticated;
grant execute on function public.travel_guide_visibility(uuid, boolean) to authenticated;
