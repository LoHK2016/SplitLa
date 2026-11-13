-- Groups, their Members, and joining by invite link.
--
-- Signed-in users may only read and rename Groups they belong to. Everything
-- else (opening a Group, joining one) goes through the functions below, so a
-- Group and its first Member always appear together and nobody can add
-- themselves without holding the invite.

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (name <> ''),
  -- Holding this is what lets a non-member join. Only Members can read it.
  invite_token uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table public.members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  -- Null for a Placeholder Member.
  user_id uuid references auth.users on delete set null,
  name text not null check (name <> ''),
  created_at timestamptz not null default now(),
  unique (group_id, user_id)
);

create index members_user_id_idx on public.members (user_id);

-- Runs with the owner's rights so the Members policy can ask "is the caller in
-- this Group?" without that question itself being filtered by the policy.
create function public.is_group_member(target_group uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.members
    where group_id = target_group and user_id = (select auth.uid())
  );
$$;

alter table public.groups enable row level security;
alter table public.members enable row level security;

revoke all on public.groups, public.members from anon, authenticated;
grant select on public.groups, public.members to authenticated;
grant update (name) on public.groups to authenticated;

create policy "Members read their Groups" on public.groups
  for select to authenticated using (public.is_group_member(id));

create policy "Members rename their Groups" on public.groups
  for update to authenticated
  using (public.is_group_member(id)) with check (public.is_group_member(id));

create policy "Members read their fellow Members" on public.members
  for select to authenticated using (public.is_group_member(group_id));

-- Opens a Group with the caller as its first Member. Returns the Group's id.
create function public.create_group(group_name text, member_name text) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  new_group uuid;
begin
  insert into public.groups (name) values (btrim(group_name)) returning id into new_group;
  insert into public.members (group_id, user_id, name)
    values (new_group, auth.uid(), btrim(member_name));
  return new_group;
end;
$$;

-- The name of the Group an invite is for, so the app can ask before joining.
create function public.invited_group_name(invite uuid) returns text
language plpgsql stable security definer set search_path = ''
as $$
declare
  found_name text;
begin
  select name into found_name from public.groups where invite_token = invite;
  if found_name is null then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  return found_name;
end;
$$;

-- Makes the caller a Member of the Group the invite is for. Returns the Group's
-- id. Does nothing if they already belong.
create function public.join_group(invite uuid, member_name text) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  target_group uuid;
begin
  select id into target_group from public.groups where invite_token = invite;
  if target_group is null then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  insert into public.members (group_id, user_id, name)
    values (target_group, auth.uid(), btrim(member_name))
    on conflict (group_id, user_id) do nothing;
  return target_group;
end;
$$;

revoke execute on function
  public.is_group_member(uuid),
  public.create_group(text, text),
  public.invited_group_name(uuid),
  public.join_group(uuid, text)
from public, anon;
grant execute on function
  public.is_group_member(uuid),
  public.create_group(text, text),
  public.invited_group_name(uuid),
  public.join_group(uuid, text)
to authenticated;

-- Members see renames and new Members as they happen.
alter publication supabase_realtime add table public.groups, public.members;
