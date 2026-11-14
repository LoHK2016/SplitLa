-- Attendance, Proposals, the Activity Budget, the Chosen Proposal, and turning
-- a Chosen Proposal into an Expense.
--
-- Only the Organiser sets the Activity Budget and picks the Chosen Proposal.
-- An Activity has at most one Chosen Proposal, and needs a date to have one.

create table public.attendance (
  activity_id uuid not null references public.activities on delete cascade,
  member_id uuid not null references public.members,
  group_id uuid not null references public.groups on delete cascade,
  status text not null check (status in ('going', 'not_going', 'no_reply')),
  primary key (activity_id, member_id)
);
create index attendance_group_id_idx on public.attendance (group_id);

create table public.proposals (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  activity_id uuid not null references public.activities on delete cascade,
  title text not null check (btrim(title) <> ''),
  amount_kind text not null check (amount_kind in ('per_person', 'total')),
  amount_cents bigint not null check (amount_cents >= 0),
  status text not null default 'open' check (status in ('open', 'chosen', 'converted')),
  created_at timestamptz not null default now()
);
create index proposals_group_id_idx on public.proposals (group_id);
create unique index proposals_one_chosen_per_activity on public.proposals (activity_id)
  where status = 'chosen';

-- The Proposal an Expense was made from, if any.
alter table public.expenses add column proposal_id uuid references public.proposals;
grant insert (proposal_id) on public.expenses to authenticated;

create function public.check_proposal() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.activities where id = new.activity_id and group_id = new.group_id
  ) then
    raise exception 'the Activity is not in this Group' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger proposals_check before insert on public.proposals
  for each row execute function public.check_proposal();

-- Recording the Expense for a Chosen Proposal retires the Proposal in the same step.
create function public.convert_proposal() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.proposal_id is not null then
    update public.proposals set status = 'converted'
      where id = new.proposal_id and activity_id = new.activity_id and status = 'chosen';
    if not found then
      raise exception 'only the Chosen Proposal of this Activity can become an Expense'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger expenses_convert_proposal before insert on public.expenses
  for each row execute function public.convert_proposal();

-- A Member sets their own Attendance, or a Placeholder Member's on their behalf.
create function public.set_attendance(target_activity uuid, target_member uuid, new_status text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  target_group uuid;
begin
  select group_id into target_group from public.activities where id = target_activity;
  if target_group is null or not public.is_group_member(target_group) then
    raise exception 'not a Member of this Group' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.members
    where id = target_member and group_id = target_group
      and (user_id = auth.uid() or user_id is null)
  ) then
    raise exception 'Attendance can only be set for yourself or a Placeholder Member'
      using errcode = '42501';
  end if;
  insert into public.attendance (activity_id, member_id, group_id, status)
    values (target_activity, target_member, target_group, new_status)
    on conflict (activity_id, member_id) do update set status = excluded.status;
end;
$$;

-- Raises unless the caller is the Organiser of the Activity.
create function public.require_organiser(target_activity uuid) returns void
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.activities
    where id = target_activity and organiser_id = public.my_member_id(group_id)
  ) then
    raise exception 'only the Organiser can do this' using errcode = '42501';
  end if;
end;
$$;

-- Sets the Activity Budget, or removes it when `new_budget_cents` is null.
create function public.set_activity_budget(target_activity uuid, new_budget_cents bigint) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_organiser(target_activity);
  update public.activities set budget_cents = new_budget_cents where id = target_activity;
end;
$$;

-- Makes a Proposal the Chosen Proposal of its Activity, replacing any other.
create function public.choose_proposal(target_proposal uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  target_activity uuid;
  current_status text;
begin
  select activity_id, status into target_activity, current_status
    from public.proposals where id = target_proposal;
  perform public.require_organiser(target_activity);
  if current_status = 'converted' then
    raise exception 'this Proposal has already become an Expense' using errcode = '23514';
  end if;
  if (select date from public.activities where id = target_activity) is null then
    raise exception 'the Activity needs a date before a Proposal can be chosen' using errcode = '23514';
  end if;
  update public.proposals set status = 'open'
    where activity_id = target_activity and status = 'chosen' and id <> target_proposal;
  update public.proposals set status = 'chosen' where id = target_proposal;
end;
$$;

-- Returns the Chosen Proposal to open, leaving the Activity with none chosen.
create function public.unchoose_proposal(target_proposal uuid) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_organiser(
    (select activity_id from public.proposals where id = target_proposal));
  update public.proposals set status = 'open' where id = target_proposal and status = 'chosen';
  if not found then
    raise exception 'this Proposal is not the Chosen Proposal' using errcode = '23514';
  end if;
end;
$$;

alter table public.attendance enable row level security;
alter table public.proposals enable row level security;
revoke all on public.attendance, public.proposals from anon, authenticated;
grant select on public.attendance, public.proposals to authenticated;
grant insert (id, group_id, activity_id, title, amount_kind, amount_cents) on public.proposals to authenticated;

create policy "Members read their Group's Attendance" on public.attendance
  for select to authenticated using (public.is_group_member(group_id));
create policy "Members read their Group's Proposals" on public.proposals
  for select to authenticated using (public.is_group_member(group_id));
create policy "Members open Proposals" on public.proposals
  for insert to authenticated with check (public.is_group_member(group_id));

revoke execute on function
  public.set_attendance(uuid, uuid, text), public.require_organiser(uuid),
  public.set_activity_budget(uuid, bigint), public.choose_proposal(uuid),
  public.unchoose_proposal(uuid)
from public, anon;
grant execute on function
  public.set_attendance(uuid, uuid, text), public.require_organiser(uuid),
  public.set_activity_budget(uuid, bigint), public.choose_proposal(uuid),
  public.unchoose_proposal(uuid)
to authenticated;
revoke execute on function public.check_proposal(), public.convert_proposal()
  from public, anon, authenticated;

alter publication supabase_realtime add table public.attendance, public.proposals;
