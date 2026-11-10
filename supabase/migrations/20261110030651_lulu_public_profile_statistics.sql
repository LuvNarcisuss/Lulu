create function private.profile_statistics(target_profile uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
    if auth.uid() is null or not exists (
        select 1 from public.profiles where user_id = auth.uid()
    ) then raise exception 'Authentication required'; end if;
    if not exists (select 1 from public.profiles where id = target_profile) then
        raise exception 'Profile unavailable';
    end if;
    return jsonb_build_object(
        'profile_id', target_profile,
        'likes', (select count(*) from public.likes l join public.clips c on c.id = l.target_id where c.publisher_id = target_profile),
        'saves', (select count(*) from public.saved_clips s join public.clips c on c.id = s.target_id where c.publisher_id = target_profile),
        'following', (select count(*) from public.follows where owner_id = target_profile),
        'followers', (select count(*) from public.follows where target_id = target_profile)
    );
end;
$$;
revoke all on function private.profile_statistics(uuid) from public, anon, authenticated;
grant execute on function private.profile_statistics(uuid) to authenticated;

create function public.travel_profile_stats(target_profile uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
    select private.profile_statistics(target_profile);
$$;
revoke all on function public.travel_profile_stats(uuid) from public, anon, authenticated;
grant execute on function public.travel_profile_stats(uuid) to authenticated;
