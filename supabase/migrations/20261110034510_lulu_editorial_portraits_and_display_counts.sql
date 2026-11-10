-- Owner-authorized illustrative baselines are separate from member interactions.
create table private.editorial_display_baselines (
    kind text not null check (kind in ('profile','clip','guide')),
    target_id uuid not null,
    metrics jsonb not null,
    primary key (kind,target_id)
);
alter table private.editorial_display_baselines enable row level security;
revoke all on private.editorial_display_baselines from public, anon, authenticated;

insert into private.editorial_display_baselines values
('profile','470f3e27-4b1c-5a4c-ae90-c3d0fe9cb291','{"likes":16,"saves":12,"following":14,"followers":18}'),
('profile','ae1fe04b-4e55-5710-b478-aa2a6f32f7d4','{"likes":13,"saves":17,"following":11,"followers":16}');
insert into private.editorial_display_baselines
select 'clip', c.id, jsonb_build_object('likes',10+((row_number() over(order by c.id)*7)%11))
from public.clips c join public.profiles p on p.id=c.publisher_id
where p.user_id is null and p.data->>'is_editorial'='true';
insert into private.editorial_display_baselines
select 'guide',guide_id,jsonb_build_object('likes',10+((row_number() over(order by guide_id)*5)%11))
from public.guide_offers where author_id is null and status='published';

update public.profiles set data=data || jsonb_build_object(
'avatar_path','https://images.pexels.com/photos/614810/pexels-photo-614810.jpeg?auto=compress&cs=tinysrgb&w=512&h=512&fit=crop',
'avatar_credit','Simon Robben / Pexels','avatar_is_illustrative',true)
where id='470f3e27-4b1c-5a4c-ae90-c3d0fe9cb291' and user_id is null;
update public.profiles set data=data || jsonb_build_object(
'avatar_path','https://images.pexels.com/photos/733872/pexels-photo-733872.jpeg?auto=compress&cs=tinysrgb&w=512&h=512&fit=crop',
'avatar_credit','Andrea Piacquadio / Pexels','avatar_is_illustrative',true)
where id='ae1fe04b-4e55-5710-b478-aa2a6f32f7d4' and user_id is null;

create or replace function private.profile_statistics(target_profile uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare baseline jsonb; actual jsonb;
begin
    if auth.uid() is null or not exists(select 1 from public.profiles where user_id=auth.uid()) then
        raise exception 'Authentication required';
    end if;
    if not exists(select 1 from public.profiles where id=target_profile) then raise exception 'Profile unavailable'; end if;
    select b.metrics into baseline from private.editorial_display_baselines b
    join public.profiles p on p.id=b.target_id and p.user_id is null and p.data->>'is_editorial'='true'
    where b.kind='profile' and b.target_id=target_profile;
    baseline:=coalesce(baseline,'{}'::jsonb);
    actual:=jsonb_build_object(
        'likes',(select count(*) from public.likes l join public.clips c on c.id=l.target_id where c.publisher_id=target_profile),
        'saves',(select count(*) from public.saved_clips s join public.clips c on c.id=s.target_id where c.publisher_id=target_profile),
        'following',(select count(*) from public.follows where owner_id=target_profile),
        'followers',(select count(*) from public.follows where target_id=target_profile));
    return jsonb_build_object('profile_id',target_profile,'actual',actual,'illustrative_baseline',baseline,
        'likes',(actual->>'likes')::bigint+coalesce((baseline->>'likes')::int,0),
        'saves',(actual->>'saves')::bigint+coalesce((baseline->>'saves')::int,0),
        'following',(actual->>'following')::bigint+coalesce((baseline->>'following')::int,0),
        'followers',(actual->>'followers')::bigint+coalesce((baseline->>'followers')::int,0));
end;
$$;

create function private.content_statistics() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare clips jsonb; guides jsonb;
begin
    if auth.uid() is null or not exists(select 1 from public.profiles where user_id=auth.uid()) then
        raise exception 'Authentication required';
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('id',c.id,
        'likes',(select count(*) from public.likes l where l.target_id=c.id)+coalesce((b.metrics->>'likes')::int,0),
        'illustrative',b.target_id is not null)),'[]'::jsonb) into clips
    from public.clips c left join private.editorial_display_baselines b on b.kind='clip' and b.target_id=c.id
    where not private.blocked(auth.uid(),c.publisher_id);
    -- Guides have no like action yet. Only explicitly approved editorial baselines are displayed.
    select coalesce(jsonb_agg(jsonb_build_object('id',g.guide_id,
        'likes',coalesce((b.metrics->>'likes')::int,0),'illustrative',b.target_id is not null)),'[]'::jsonb) into guides
    from public.guide_offers g left join private.editorial_display_baselines b on b.kind='guide' and b.target_id=g.guide_id
    where g.status='published' and (g.author_id is null or not private.blocked(auth.uid(),g.author_id));
    return jsonb_build_object('clips',clips,'guides',guides);
end;
$$;
revoke all on function private.content_statistics() from public,anon,authenticated;
grant execute on function private.content_statistics() to authenticated;
create function public.travel_content_stats() returns jsonb
language sql stable security invoker set search_path='' as $$ select private.content_statistics(); $$;
revoke all on function public.travel_content_stats() from public,anon,authenticated;
grant execute on function public.travel_content_stats() to authenticated;
