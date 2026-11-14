-- Activities, Expenses, and the history of every change to an Expense.
--
-- Any Member may add, change or delete (soft-delete) any Expense in their Group.
-- Every such change is written to change_log by a trigger; nobody can write
-- to, alter or remove that log directly.

-- The caller's own Member row in a Group, or null if they do not belong.
create function public.my_member_id(target_group uuid) returns uuid
language sql stable security definer set search_path = ''
as $$
  select id from public.members
  where group_id = target_group and user_id = (select auth.uid());
$$;

create function public.member_in_group(target_member uuid, target_group uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.members where id = target_member and group_id = target_group
  );
$$;

create table public.activities (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  name text not null check (btrim(name) <> ''),
  -- A calendar day, with no time zone: the day the Activity happens.
  date date,
  -- The Organiser: the Member who opened the Activity.
  organiser_id uuid not null references public.members,
  -- The Activity Budget. Only the Organiser sets it, through set_activity_budget.
  budget_cents bigint check (budget_cents >= 0),
  created_at timestamptz not null default now()
);
create index activities_group_id_idx on public.activities (group_id);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  activity_id uuid not null references public.activities on delete cascade,
  title text not null check (btrim(title) <> ''),
  date date not null,
  -- The amount as entered, before any service charge.
  amount_cents bigint not null check (amount_cents >= 0),
  paid_by uuid not null references public.members,
  -- Who shares it: {"kind":"equal","members":[member id, ...]}
  --            or  {"kind":"exact","amounts":{member id: cents, ...}}
  split jsonb not null,
  has_service_charge boolean not null default false,
  -- Set when the Expense is deleted. Deleted Expenses stay for the record.
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create index expenses_group_id_idx on public.expenses (group_id);

create table public.change_log (
  id bigint generated always as identity primary key,
  group_id uuid not null references public.groups on delete cascade,
  entity text not null,
  entity_id uuid not null,
  action text not null check (action in ('created', 'updated', 'deleted', 'restored')),
  actor_id uuid references public.members on delete set null,
  actor_name text not null,
  at timestamptz not null default now(),
  before jsonb,
  after jsonb not null
);
create index change_log_entity_idx on public.change_log (group_id, entity_id);

-- Refuses a split that names nobody, names someone outside the Group, or (for
-- exact amounts) does not add up to the Expense amount.
create function public.check_split(split jsonb, amount_cents bigint, target_group uuid) returns void
language plpgsql stable security definer set search_path = ''
as $$
declare
  ids uuid[];
  total bigint;
begin
  if split->>'kind' = 'equal' and jsonb_typeof(split->'members') = 'array' then
    select array_agg(value::uuid) into ids from jsonb_array_elements_text(split->'members');
  elsif split->>'kind' = 'exact' and jsonb_typeof(split->'amounts') = 'object' then
    select array_agg(key::uuid), sum(value::bigint) into ids, total
      from jsonb_each_text(split->'amounts');
    if exists (select 1 from jsonb_each_text(split->'amounts') where value::bigint < 0) then
      raise exception 'a Share cannot be negative' using errcode = '23514';
    end if;
    if total is distinct from amount_cents then
      raise exception 'exact amounts must add up to the Expense amount' using errcode = '23514';
    end if;
  else
    raise exception 'unknown split' using errcode = '23514';
  end if;
  if ids is null then
    raise exception 'an Expense needs someone to share it' using errcode = '23514';
  end if;
  if exists (
    select 1 from unnest(ids) as wanted(id)
    where not exists (
      select 1 from public.members where members.id = wanted.id and group_id = target_group)
  ) then
    raise exception 'everyone sharing an Expense must be in the Group' using errcode = '23514';
  end if;
end;
$$;

create function public.check_expense() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.activities where id = new.activity_id and group_id = new.group_id
  ) then
    raise exception 'the Activity is not in this Group' using errcode = '23514';
  end if;
  if not public.member_in_group(new.paid_by, new.group_id) then
    raise exception 'the payer is not in this Group' using errcode = '23514';
  end if;
  perform public.check_split(new.split, new.amount_cents, new.group_id);
  return new;
end;
$$;

create trigger expenses_check before insert or update on public.expenses
  for each row execute function public.check_expense();

create function public.check_activity() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.member_in_group(new.organiser_id, new.group_id) then
    raise exception 'the Organiser is not in this Group' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger activities_check before insert on public.activities
  for each row execute function public.check_activity();

-- Writes one change_log row per insert or update. The trigger argument names the entity.
create function public.record_change() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  what text;
  actor uuid;
  actor_called text;
begin
  if tg_op = 'INSERT' then
    what := 'created';
  elsif old.deleted_at is null and new.deleted_at is not null then
    what := 'deleted';
  elsif old.deleted_at is not null and new.deleted_at is null then
    what := 'restored';
  else
    what := 'updated';
  end if;
  select id, name into actor, actor_called from public.members
    where group_id = new.group_id and user_id = auth.uid();
  insert into public.change_log (group_id, entity, entity_id, action, actor_id, actor_name, before, after)
  values (
    new.group_id, tg_argv[0], new.id, what, actor, coalesce(actor_called, ''),
    case when tg_op = 'UPDATE' then to_jsonb(old) end, to_jsonb(new));
  return null;
end;
$$;

create trigger expenses_record_change after insert or update on public.expenses
  for each row execute function public.record_change('expense');

alter table public.activities enable row level security;
alter table public.expenses enable row level security;
alter table public.change_log enable row level security;

revoke all on public.activities, public.expenses, public.change_log from anon, authenticated;
grant select on public.activities, public.expenses, public.change_log to authenticated;
grant insert (id, group_id, name, date, organiser_id, budget_cents) on public.activities to authenticated;
grant insert (id, group_id, activity_id, title, date, amount_cents, paid_by, split, has_service_charge)
  on public.expenses to authenticated;
grant update (title, date, amount_cents, paid_by, split, has_service_charge, deleted_at)
  on public.expenses to authenticated;

create policy "Members read their Group's Activities" on public.activities
  for select to authenticated using (public.is_group_member(group_id));
create policy "Members open Activities as their Organiser" on public.activities
  for insert to authenticated
  with check (organiser_id = public.my_member_id(group_id));

create policy "Members read their Group's Expenses" on public.expenses
  for select to authenticated using (public.is_group_member(group_id));
create policy "Members add Expenses" on public.expenses
  for insert to authenticated with check (public.is_group_member(group_id));
create policy "Members change Expenses" on public.expenses
  for update to authenticated
  using (public.is_group_member(group_id)) with check (public.is_group_member(group_id));

create policy "Members read their Group's history" on public.change_log
  for select to authenticated using (public.is_group_member(group_id));

revoke execute on function
  public.my_member_id(uuid), public.member_in_group(uuid, uuid),
  public.check_split(jsonb, bigint, uuid)
from public, anon;
grant execute on function
  public.my_member_id(uuid), public.member_in_group(uuid, uuid),
  public.check_split(jsonb, bigint, uuid)
to authenticated;
revoke execute on function public.check_expense(), public.check_activity(), public.record_change()
  from public, anon, authenticated;

alter publication supabase_realtime add table public.activities, public.expenses, public.change_log;
