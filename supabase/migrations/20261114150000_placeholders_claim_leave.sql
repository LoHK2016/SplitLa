-- Placeholder Members, claiming one when joining, and leaving a Group.
--
-- A Placeholder Member is a members row with no user behind it. Claiming links
-- the row to the joining user; leaving unlinks it. The row, and so every
-- Expense and Settlement that names it, never changes.

grant insert (group_id, name) on public.members to authenticated;

create policy "Members add Placeholder Members" on public.members
  for insert to authenticated
  with check (public.is_group_member(group_id) and user_id is null);

-- The Placeholder Members of the Group an invite is for, so someone joining
-- can pick the one that is them.
create function public.invite_placeholders(invite uuid) returns table (id uuid, name text)
language sql stable security definer set search_path = ''
as $$
  select members.id, members.name
  from public.members join public.groups on groups.id = members.group_id
  where groups.invite_token = invite and members.user_id is null
  order by members.created_at, members.id;
$$;

drop function public.join_group(uuid, text);

-- Makes the caller a Member of the Group the invite is for and returns the
-- Group's id. With `claim`, they take over that Placeholder Member instead of
-- becoming a new Member. Does nothing if they already belong.
create function public.join_group(invite uuid, member_name text, claim uuid default null) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  target_group uuid;
begin
  select id into target_group from public.groups where invite_token = invite;
  if target_group is null then
    raise exception 'invite not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from public.members where group_id = target_group and user_id = auth.uid()
  ) then
    return target_group;
  end if;
  if claim is null then
    insert into public.members (group_id, user_id, name)
      values (target_group, auth.uid(), btrim(member_name));
  else
    update public.members set user_id = auth.uid()
      where id = claim and group_id = target_group and user_id is null;
    if not found then
      raise exception 'that Placeholder Member cannot be claimed' using errcode = 'P0002';
    end if;
  end if;
  return target_group;
end;
$$;

-- The caller leaves a Group: their Member row stays, as a Placeholder Member,
-- so their Balance stays with it.
create function public.leave_group(target_group uuid) returns void
language sql security definer set search_path = ''
as $$
  update public.members set user_id = null
  where group_id = target_group and user_id = auth.uid();
$$;

revoke execute on function
  public.invite_placeholders(uuid), public.join_group(uuid, text, uuid), public.leave_group(uuid)
from public, anon;
grant execute on function
  public.invite_placeholders(uuid), public.join_group(uuid, text, uuid), public.leave_group(uuid)
to authenticated;
