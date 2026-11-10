create function private.can_view_guide_author(author uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select auth.uid() is not null and (author is null or not private.blocked(auth.uid(), author));
$$;
revoke all on function private.can_view_guide_author(uuid) from public, anon, authenticated;
grant execute on function private.can_view_guide_author(uuid) to authenticated;

alter policy read_visible_guide_offers on public.guide_offers using (
    author_id = (select auth.uid()) or
    (status = 'published' and private.can_view_guide_author(author_id))
);
