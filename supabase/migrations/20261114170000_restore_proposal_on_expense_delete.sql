-- Deleting the Expense a Chosen Proposal became puts the Proposal back as the
-- Chosen Proposal, so its Share counts towards Committed Spend again instead of
-- disappearing. Restoring the Expense retires the Proposal again.
--
-- If the Organiser has chosen another Proposal in the meantime, that choice
-- stands: the Proposal goes back to open rather than taking it over.

create function public.follow_expense_deletion() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.proposal_id is null then
    return null;
  end if;
  if old.deleted_at is null and new.deleted_at is not null then
    update public.proposals
      set status = case
        when exists (
          select 1 from public.proposals other
          where other.activity_id = new.activity_id and other.status = 'chosen')
        then 'open' else 'chosen' end
      where id = new.proposal_id and status = 'converted';
  elsif old.deleted_at is not null and new.deleted_at is null then
    update public.proposals set status = 'converted' where id = new.proposal_id;
  end if;
  return null;
end;
$$;

create trigger expenses_follow_deletion after update of deleted_at on public.expenses
  for each row execute function public.follow_expense_deletion();

revoke execute on function public.follow_expense_deletion() from public, anon, authenticated;
