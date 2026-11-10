begin;

alter table public.guide_offers
    add column retained_community boolean not null default false;

create table private.account_deletion_requests (
    user_id uuid primary key references auth.users(id) on delete cascade
);
revoke all on private.account_deletion_requests from public, anon, authenticated;

-- Serialize new upload transactions with the first phase of account deletion.
create function private.can_upload_for_account() returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    account_id uuid := auth.uid();
begin
    perform 1 from auth.users where id = account_id for key share;
    if not found then return false; end if;
    return not exists (
        select 1 from private.account_deletion_requests where user_id = account_id
    );
end;
$$;
revoke all on function private.can_upload_for_account() from public, anon, authenticated;
grant execute on function private.can_upload_for_account() to authenticated;

alter policy upload_own on storage.objects with check (
    bucket_id = 'uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select private.can_upload_for_account())
);

create policy read_retained_community_upload on storage.objects for select to authenticated
using (
    bucket_id = 'uploads'
    and (storage.foldername(name))[1] = 'community'
    and exists (
        select 1 from public.clips c
        where 'uploads/' || storage.objects.name in (c.data->>'video_path', c.data->>'cover_path')
    )
);

-- Include only paths already referenced by published clips. Private submissions
-- are separate rows and never become public as part of account deletion.
create function private.account_clip_media(target_user uuid)
returns table (clip_id uuid, media_key text, source text, destination text)
language sql stable set search_path = '' as $$
    select c.id, media.key, substr(media.path, 9),
           'community/' || c.id::text || '/' || media.key || '-' || md5(media.path)
             || coalesce(substring(media.path from '\.[a-zA-Z0-9]+$'), '')
    from public.clips c
    cross join lateral (values ('video_path', c.data->>'video_path'), ('cover_path', c.data->>'cover_path')) media(key, path)
    where media.path like 'uploads/' || target_user::text || '/%';
$$;
revoke all on function private.account_clip_media(uuid) from public, anon, authenticated;

create function public.travel_account_media(target_user uuid, publish boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    media record;
    copy_plan jsonb;
begin
    perform 1 from auth.users where id = target_user for update;
    if not found then raise exception 'Account unavailable'; end if;
    insert into private.account_deletion_requests (user_id)
    values (target_user) on conflict do nothing;

    if publish then
        for media in select * from private.account_clip_media(target_user) loop
            if not exists (
                select 1 from storage.objects
                where bucket_id = 'uploads' and name = media.destination
            ) then
                raise exception 'Retained community media is incomplete';
            end if;
            update public.clips
            set data = jsonb_set(data, array[media.media_key], to_jsonb('uploads/' || media.destination))
            where id = media.clip_id and data->>media.media_key = 'uploads/' || media.source;
        end loop;
        return '[]'::jsonb;
    end if;

    select coalesce(jsonb_agg(jsonb_build_object('source', m.source, 'destination', m.destination)), '[]'::jsonb)
    into copy_plan
    from private.account_clip_media(target_user) m
    where not exists (
        select 1 from storage.objects
        where bucket_id = 'uploads' and name = m.destination
    );
    return copy_plan;
end;
$$;
revoke all on function public.travel_account_media(uuid, boolean) from public, anon, authenticated;
grant execute on function public.travel_account_media(uuid, boolean) to service_role;

create function private.retain_community_on_account_deletion() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    if exists (select 1 from private.account_clip_media(old.id)) or exists (
        select 1 from storage.objects
        where bucket_id = 'uploads' and name like old.id::text || '/%'
    ) then
        raise exception 'Finish account media cleanup before deleting the identity';
    end if;

    update public.clips c
    set publisher_id = null,
        data = (c.data - array['publisher_id', 'owner_id', 'user_id', 'author_id', 'author'])
               || jsonb_build_object('retained_community', true)
    where exists (
        select 1 from public.profiles p where p.id = c.publisher_id and p.user_id = old.id
    );

    update public.guide_offers
    set author_id = null, retained_community = true
    where author_id = old.id and status = 'published';

    delete from public.guides g using public.guide_offers o
    where g.id = o.guide_id and o.author_id = old.id and o.status <> 'published';

    -- The surviving participant keeps their own messages without the old direct key.
    update public.conversations c set direct_key = null
    where c.direct_key is not null and exists (
        select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = old.id
    );

    delete from public.conversations c where exists (
        select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id = old.id
    ) and not exists (
        select 1 from public.conversation_members m where m.conversation_id = c.id and m.user_id <> old.id
    );

    return old;
end;
$$;
revoke all on function private.retain_community_on_account_deletion() from public, anon, authenticated;
create trigger retain_community_on_account_deletion
before delete on auth.users
for each row execute function private.retain_community_on_account_deletion();

commit;
