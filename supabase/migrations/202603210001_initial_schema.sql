create extension if not exists "pgcrypto";

create type public.scope_type as enum ('organization', 'group');
create type public.membership_status as enum ('active', 'invited', 'suspended');
create type public.role_code as enum ('organization_admin', 'organization_member', 'group_admin', 'group_member', 'group_read_only');
create type public.sync_status as enum ('pending_create', 'pending_update', 'pending_delete', 'synced', 'conflict');
create type public.session_item_type as enum ('song', 'attachment', 'note');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, id)
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  group_id uuid,
  user_id uuid not null references auth.users(id) on delete cascade,
  scope_type public.scope_type not null,
  role_code public.role_code not null,
  status public.membership_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint memberships_group_scope_fk
    foreign key (organization_id, group_id)
    references public.groups(organization_id, id)
    on delete cascade,
  constraint memberships_scope_group_consistency
    check (
      (scope_type = 'organization' and group_id is null)
      or (scope_type = 'group' and group_id is not null)
    ),
  constraint memberships_role_scope_consistency
    check (
      (scope_type = 'organization' and role_code in ('organization_admin', 'organization_member'))
      or (scope_type = 'group' and role_code in ('group_admin', 'group_member', 'group_read_only'))
    ),
  unique (organization_id, group_id, user_id, role_code)
);

create table public.songs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  title text not null,
  artist text,
  key_signature text,
  tempo_bpm integer,
  tags text[] not null default '{}',
  chordpro_source text not null,
  metadata_json jsonb not null default '{}'::jsonb,
  version bigint not null default 1,
  base_version bigint,
  sync_status public.sync_status not null default 'synced',
  updated_at timestamptz not null default timezone('utc', now()),
  last_modified_by uuid references auth.users(id),
  constraint songs_version_check
    check (version > 0 and (base_version is null or base_version > 0)),
  constraint songs_tempo_check
    check (tempo_bpm is null or tempo_bpm > 0),
  unique (organization_id, id)
);

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  group_id uuid,
  name text not null,
  description text,
  scheduled_for timestamptz,
  version bigint not null default 1,
  base_version bigint,
  sync_status public.sync_status not null default 'synced',
  updated_at timestamptz not null default timezone('utc', now()),
  last_modified_by uuid references auth.users(id),
  constraint plans_group_scope_fk
    foreign key (organization_id, group_id)
    references public.groups(organization_id, id),
  constraint plans_version_check
    check (version > 0 and (base_version is null or base_version > 0)),
  unique (organization_id, id)
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  group_id uuid,
  plan_id uuid,
  name text not null,
  starts_at timestamptz,
  ends_at timestamptz,
  location text,
  version bigint not null default 1,
  base_version bigint,
  sync_status public.sync_status not null default 'synced',
  updated_at timestamptz not null default timezone('utc', now()),
  last_modified_by uuid references auth.users(id),
  constraint events_group_scope_fk
    foreign key (organization_id, group_id)
    references public.groups(organization_id, id),
  constraint events_plan_scope_fk
    foreign key (organization_id, plan_id)
    references public.plans(organization_id, id),
  constraint events_time_window_check
    check (starts_at is null or ends_at is null or ends_at >= starts_at),
  constraint events_version_check
    check (version > 0 and (base_version is null or base_version > 0)),
  unique (organization_id, id)
);

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  group_id uuid,
  event_id uuid not null,
  name text not null,
  notes text,
  version bigint not null default 1,
  base_version bigint,
  sync_status public.sync_status not null default 'synced',
  updated_at timestamptz not null default timezone('utc', now()),
  last_modified_by uuid references auth.users(id),
  constraint sessions_group_scope_fk
    foreign key (organization_id, group_id)
    references public.groups(organization_id, id),
  constraint sessions_event_scope_fk
    foreign key (organization_id, event_id)
    references public.events(organization_id, id)
    on delete cascade,
  constraint sessions_version_check
    check (version > 0 and (base_version is null or base_version > 0)),
  unique (organization_id, id)
);

create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  song_id uuid not null,
  storage_bucket text not null,
  storage_path text not null,
  mime_type text not null,
  file_name text not null,
  version bigint not null default 1,
  base_version bigint,
  sync_status public.sync_status not null default 'synced',
  updated_at timestamptz not null default timezone('utc', now()),
  last_modified_by uuid references auth.users(id),
  constraint attachments_song_scope_fk
    foreign key (organization_id, song_id)
    references public.songs(organization_id, id)
    on delete cascade,
  constraint attachments_version_check
    check (version > 0 and (base_version is null or base_version > 0)),
  unique (organization_id, id)
);

create table public.session_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  session_id uuid not null,
  song_id uuid,
  attachment_id uuid,
  item_type public.session_item_type not null,
  title_override text,
  position integer not null,
  notes text,
  version bigint not null default 1,
  base_version bigint,
  sync_status public.sync_status not null default 'synced',
  updated_at timestamptz not null default timezone('utc', now()),
  last_modified_by uuid references auth.users(id),
  constraint session_items_session_scope_fk
    foreign key (organization_id, session_id)
    references public.sessions(organization_id, id)
    on delete cascade,
  constraint session_items_song_scope_fk
    foreign key (organization_id, song_id)
    references public.songs(organization_id, id),
  constraint session_items_attachment_scope_fk
    foreign key (organization_id, attachment_id)
    references public.attachments(organization_id, id),
  constraint session_items_reference_consistency
    check (
      (item_type = 'song' and song_id is not null and attachment_id is null)
      or (item_type = 'attachment' and attachment_id is not null and song_id is null)
      or (item_type = 'note' and song_id is null and attachment_id is null)
    ),
  constraint session_items_version_check
    check (version > 0 and (base_version is null or base_version > 0)),
  unique (session_id, position)
);

create index groups_organization_idx on public.groups (organization_id);
create index memberships_user_idx on public.memberships (user_id);
create index memberships_organization_idx on public.memberships (organization_id);
create index memberships_group_idx on public.memberships (group_id);
create index songs_organization_idx on public.songs (organization_id);
create index plans_organization_idx on public.plans (organization_id);
create index events_organization_idx on public.events (organization_id);
create index sessions_organization_idx on public.sessions (organization_id);
create index session_items_session_idx on public.session_items (session_id, position);
create index attachments_organization_idx on public.attachments (organization_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create or replace function public.current_organization_ids()
returns setof uuid
language sql
stable
as $$
  select distinct membership.organization_id
  from public.memberships as membership
  where membership.user_id = auth.uid()
    and membership.status = 'active';
$$;

create or replace function public.has_capability(
  target_organization_id uuid,
  capability text,
  target_group_id uuid default null
)
returns boolean
language plpgsql
stable
as $$
declare
  matched_role public.role_code;
begin
  select membership.role_code
  into matched_role
  from public.memberships as membership
  where membership.user_id = auth.uid()
    and membership.organization_id = target_organization_id
    and membership.status = 'active'
    and (
      membership.scope_type = 'organization'
      or (target_group_id is not null and membership.group_id = target_group_id)
    )
  order by case membership.role_code
    when 'organization_admin' then 1
    when 'group_admin' then 2
    when 'organization_member' then 3
    when 'group_member' then 4
    else 5
  end
  limit 1;

  if matched_role is null then
    return false;
  end if;

  return case capability
    when 'canViewSongs' then matched_role in ('organization_admin', 'organization_member', 'group_admin', 'group_member', 'group_read_only')
    when 'canEditSongs' then matched_role in ('organization_admin', 'organization_member', 'group_admin', 'group_member')
    when 'canManageOrganizationMembers' then matched_role = 'organization_admin'
    when 'canManageGroupMembers' then matched_role in ('organization_admin', 'group_admin')
    when 'canEditSessions' then matched_role in ('organization_admin', 'organization_member', 'group_admin', 'group_member')
    when 'canManagePlans' then matched_role in ('organization_admin', 'organization_member', 'group_admin', 'group_member')
    else false
  end;
end;
$$;

create or replace function public.can_manage_membership(
  target_organization_id uuid,
  target_scope_type public.scope_type,
  target_group_id uuid default null
)
returns boolean
language sql
stable
as $$
  select case
    when target_scope_type = 'organization'
      then public.has_capability(
        target_organization_id,
        'canManageOrganizationMembers'
      )
    when target_scope_type = 'group'
      then public.has_capability(
        target_organization_id,
        'canManageGroupMembers',
        target_group_id
      )
    else false
  end;
$$;

create or replace function public.session_group_id(
  target_organization_id uuid,
  target_session_id uuid
)
returns uuid
language sql
stable
as $$
  select session_row.group_id
  from public.sessions as session_row
  where session_row.organization_id = target_organization_id
    and session_row.id = target_session_id;
$$;

alter table public.organizations enable row level security;
alter table public.groups enable row level security;
alter table public.memberships enable row level security;
alter table public.songs enable row level security;
alter table public.plans enable row level security;
alter table public.events enable row level security;
alter table public.sessions enable row level security;
alter table public.session_items enable row level security;
alter table public.attachments enable row level security;

create policy "organizations are visible to members"
on public.organizations
for select
using (id in (select public.current_organization_ids()));

create policy "groups are visible to org members"
on public.groups
for select
using (organization_id in (select public.current_organization_ids()));

create policy "memberships are visible inside organization"
on public.memberships
for select
using (organization_id in (select public.current_organization_ids()));

create policy "memberships are manageable by capability"
on public.memberships
for all
using (public.can_manage_membership(organization_id, scope_type, group_id))
with check (public.can_manage_membership(organization_id, scope_type, group_id));

create policy "songs are visible with song view capability"
on public.songs
for select
using (public.has_capability(organization_id, 'canViewSongs'));

create policy "songs are editable with song edit capability"
on public.songs
for all
using (public.has_capability(organization_id, 'canEditSongs'))
with check (public.has_capability(organization_id, 'canEditSongs'));

create policy "plans are editable with plan capability"
on public.plans
for all
using (public.has_capability(organization_id, 'canManagePlans', group_id))
with check (public.has_capability(organization_id, 'canManagePlans', group_id));

create policy "events are editable with session capability"
on public.events
for all
using (public.has_capability(organization_id, 'canEditSessions', group_id))
with check (public.has_capability(organization_id, 'canEditSessions', group_id));

create policy "sessions are editable with session capability"
on public.sessions
for all
using (public.has_capability(organization_id, 'canEditSessions', group_id))
with check (public.has_capability(organization_id, 'canEditSessions', group_id));

create policy "session items inherit session edit capability"
on public.session_items
for all
using (
  public.has_capability(
    organization_id,
    'canEditSessions',
    public.session_group_id(organization_id, session_id)
  )
)
with check (
  public.has_capability(
    organization_id,
    'canEditSessions',
    public.session_group_id(organization_id, session_id)
  )
);

create policy "attachments are visible to song viewers"
on public.attachments
for select
using (public.has_capability(organization_id, 'canViewSongs'));

create policy "attachments are editable to song editors"
on public.attachments
for all
using (public.has_capability(organization_id, 'canEditSongs'))
with check (public.has_capability(organization_id, 'canEditSongs'));

create trigger organizations_set_updated_at
before update on public.organizations
for each row execute procedure public.set_updated_at();

create trigger groups_set_updated_at
before update on public.groups
for each row execute procedure public.set_updated_at();

create trigger memberships_set_updated_at
before update on public.memberships
for each row execute procedure public.set_updated_at();

create trigger songs_set_updated_at
before update on public.songs
for each row execute procedure public.set_updated_at();

create trigger plans_set_updated_at
before update on public.plans
for each row execute procedure public.set_updated_at();

create trigger events_set_updated_at
before update on public.events
for each row execute procedure public.set_updated_at();

create trigger sessions_set_updated_at
before update on public.sessions
for each row execute procedure public.set_updated_at();

create trigger session_items_set_updated_at
before update on public.session_items
for each row execute procedure public.set_updated_at();

create trigger attachments_set_updated_at
before update on public.attachments
for each row execute procedure public.set_updated_at();
