-- An Expense split by plates (as at a conveyor-belt sushi restaurant) keeps the plates, so it
-- can be shown and edited plate by plate later. The money still comes from the exact amounts;
-- the plates must agree with them exactly, so the two can never tell different stories.
--
-- plates: {"types":  [{"kind": "red"|"silver"|"gold"|"black"|"custom",
--                      "name": text, "price_cents": int, "color_index": int}, ...],
--          "counts": {member id: [plates of each type, in the order of types], ...}}

alter table public.expenses add column plates jsonb;
grant insert (plates), update (plates) on public.expenses to authenticated;

-- Refuses plates that are malformed, or whose totals differ from the Expense's exact amounts.
create function public.check_plates(plates jsonb, split jsonb, amount_cents bigint) returns void
language plpgsql immutable set search_path = ''
as $$
declare
  prices bigint[];
  member text;
  counts jsonb;
  computed jsonb := '{}';
  total bigint;
begin
  if split->>'kind' is distinct from 'exact' then
    raise exception 'plates only go with exact amounts' using errcode = '23514';
  end if;
  if jsonb_typeof(plates->'types') <> 'array' or jsonb_typeof(plates->'counts') <> 'object' then
    raise exception 'plates need types and counts' using errcode = '23514';
  end if;
  select array_agg((t->>'price_cents')::bigint order by ord) into prices
    from jsonb_array_elements(plates->'types') with ordinality as x(t, ord);
  if exists (select 1 from unnest(prices) p where p is null or p < 0) then
    raise exception 'every plate needs a price of zero or more' using errcode = '23514';
  end if;
  for member, counts in select * from jsonb_each(plates->'counts') loop
    if jsonb_typeof(counts) <> 'array' or jsonb_array_length(counts) > coalesce(array_length(prices, 1), 0)
       or exists (select 1 from jsonb_array_elements_text(counts) c where c::int < 0) then
      raise exception 'plate counts must be zero or more, one per plate type' using errcode = '23514';
    end if;
    select coalesce(sum(c::bigint * prices[ord]), 0) into total
      from jsonb_array_elements_text(counts) with ordinality as x(c, ord);
    if total > 0 then
      computed := computed || jsonb_build_object(member, total);
    end if;
  end loop;
  if computed <> (split->'amounts') then
    raise exception 'plate counts do not add up to the amounts' using errcode = '23514';
  end if;
end;
$$;

create or replace function public.check_expense() returns trigger
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
  if new.plates is not null then
    perform public.check_plates(new.plates, new.split, new.amount_cents);
  end if;
  return new;
end;
$$;

revoke execute on function public.check_plates(jsonb, jsonb, bigint) from public, anon;
grant execute on function public.check_plates(jsonb, jsonb, bigint) to authenticated;
