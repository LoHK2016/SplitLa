-- Settlements: a record that one Member paid another outside the app.
-- Any Member may add, change or soft-delete one; each change goes to change_log.

create table public.settlements (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups on delete cascade,
  from_member uuid not null references public.members,
  to_member uuid not null references public.members,
  amount_cents bigint not null check (amount_cents > 0),
  date date not null,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  check (from_member <> to_member)
);
create index settlements_group_id_idx on public.settlements (group_id);

create function public.check_settlement() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.member_in_group(new.from_member, new.group_id)
     or not public.member_in_group(new.to_member, new.group_id) then
    raise exception 'both sides of a Settlement must be in the Group' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger settlements_check before insert or update on public.settlements
  for each row execute function public.check_settlement();
create trigger settlements_record_change after insert or update on public.settlements
  for each row execute function public.record_change('settlement');

alter table public.settlements enable row level security;
revoke all on public.settlements from anon, authenticated;
grant select on public.settlements to authenticated;
grant insert (id, group_id, from_member, to_member, amount_cents, date) on public.settlements to authenticated;
grant update (from_member, to_member, amount_cents, date, deleted_at) on public.settlements to authenticated;

create policy "Members read their Group's Settlements" on public.settlements
  for select to authenticated using (public.is_group_member(group_id));
create policy "Members record Settlements" on public.settlements
  for insert to authenticated with check (public.is_group_member(group_id));
create policy "Members change Settlements" on public.settlements
  for update to authenticated
  using (public.is_group_member(group_id)) with check (public.is_group_member(group_id));

revoke execute on function public.check_settlement() from public, anon, authenticated;

alter publication supabase_realtime add table public.settlements;
