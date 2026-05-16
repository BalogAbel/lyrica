alter table public.songs
  drop constraint if exists songs_last_modified_by_fkey,
  add constraint songs_last_modified_by_fkey
    foreign key (last_modified_by) references auth.users(id)
    on delete set null;

alter table public.plans
  drop constraint if exists plans_last_modified_by_fkey,
  add constraint plans_last_modified_by_fkey
    foreign key (last_modified_by) references auth.users(id)
    on delete set null;

alter table public.sessions
  drop constraint if exists sessions_last_modified_by_fkey,
  add constraint sessions_last_modified_by_fkey
    foreign key (last_modified_by) references auth.users(id)
    on delete set null;

alter table public.attachments
  drop constraint if exists attachments_last_modified_by_fkey,
  add constraint attachments_last_modified_by_fkey
    foreign key (last_modified_by) references auth.users(id)
    on delete set null;

alter table public.session_items
  drop constraint if exists session_items_last_modified_by_fkey,
  add constraint session_items_last_modified_by_fkey
    foreign key (last_modified_by) references auth.users(id)
    on delete set null;
