-- Both member and editorial authors have profiles. Member profiles still cascade from Auth.
alter table public.comments
    drop constraint comments_user_id_fkey,
    add constraint comments_user_id_fkey foreign key (user_id)
        references public.profiles(id) on delete cascade;
