-- Who can read and write Activities, Expenses, Settlements, the change history,
-- Attendance and Proposals, tested as real signed-in users.
-- Run with: npx supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(55);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'amy@rls-test.invalid'),
  ('00000000-0000-0000-0000-00000000000b', 'ben@rls-test.invalid'),
  ('00000000-0000-0000-0000-00000000000c', 'cat@rls-test.invalid');

-- Amy opens a Group, Ben joins it. Cat stays outside. -------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select set_config('t.group', create_group('飯腳', 'Amy')::text, true);
select set_config('t.amy', my_member_id(current_setting('t.group')::uuid)::text, true);
select set_config('t.invite', (select invite_token::text from groups), true);

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select join_group(current_setting('t.invite')::uuid, 'Ben');
select set_config('t.ben', my_member_id(current_setting('t.group')::uuid)::text, true);

-- 03: Activities and Expenses ---------------------------------------------------------
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select lives_ok($$
  insert into activities (id, group_id, name, date, organiser_id)
  values ('aaaaaaaa-0000-0000-0000-000000000001', current_setting('t.group')::uuid, '火鍋',
          '2026-12-05', current_setting('t.amy')::uuid) $$,
  'a Member opens an Activity as its Organiser');
select throws_ok($$
  insert into activities (group_id, name, organiser_id)
  values (current_setting('t.group')::uuid, 'X', current_setting('t.ben')::uuid) $$,
  '42501', null, 'nobody can open an Activity in someone else''s name');

select lives_ok($$
  insert into expenses (id, group_id, activity_id, title, date, amount_cents, paid_by, split)
  values ('eeeeeeee-0000-0000-0000-000000000001', current_setting('t.group')::uuid,
          'aaaaaaaa-0000-0000-0000-000000000001', '火鍋', '2026-12-05', 10000,
          current_setting('t.amy')::uuid,
          jsonb_build_object('kind', 'equal', 'members',
            jsonb_build_array(current_setting('t.amy'), current_setting('t.ben')))) $$,
  'a Member records an Expense shared equally');
select throws_ok($$
  insert into expenses (group_id, activity_id, title, date, amount_cents, paid_by, split)
  values (current_setting('t.group')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001', 'X',
          '2026-12-05', 100, current_setting('t.amy')::uuid,
          '{"kind":"equal","members":[]}') $$,
  '23514', null, 'an Expense needs someone to share it');
select throws_ok($$
  insert into expenses (group_id, activity_id, title, date, amount_cents, paid_by, split)
  values (current_setting('t.group')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001', 'X',
          '2026-12-05', 100, current_setting('t.amy')::uuid,
          '{"kind":"equal","members":["99999999-9999-9999-9999-999999999999"]}') $$,
  '23514', null, 'everyone sharing an Expense must be in the Group');

-- 04: exact amounts
select lives_ok($$
  insert into expenses (id, group_id, activity_id, title, date, amount_cents, paid_by, split, has_service_charge)
  values ('eeeeeeee-0000-0000-0000-000000000002', current_setting('t.group')::uuid,
          'aaaaaaaa-0000-0000-0000-000000000001', '飲品', '2026-12-05', 300,
          current_setting('t.ben')::uuid,
          jsonb_build_object('kind', 'exact', 'amounts',
            jsonb_build_object(current_setting('t.amy'), 100, current_setting('t.ben'), 200)), true) $$,
  'an Expense can carry exact amounts and the service charge');
select throws_ok($$
  insert into expenses (group_id, activity_id, title, date, amount_cents, paid_by, split)
  values (current_setting('t.group')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001', 'X',
          '2026-12-05', 300, current_setting('t.amy')::uuid,
          jsonb_build_object('kind', 'exact', 'amounts', jsonb_build_object(current_setting('t.amy'), 100))) $$,
  '23514', null, 'exact amounts must add up to the Expense amount');

-- Cat, a non-member, reads and writes nothing
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000c"}';
select is_empty('select * from activities', 'a non-member cannot read Activities');
select is_empty('select * from expenses', 'a non-member cannot read Expenses');
select is_empty('select * from change_log', 'a non-member cannot read the history');
select throws_ok($$
  insert into expenses (group_id, activity_id, title, date, amount_cents, paid_by, split)
  values (current_setting('t.group')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001', 'X',
          '2026-12-05', 100, current_setting('t.amy')::uuid,
          jsonb_build_object('kind', 'equal', 'members', jsonb_build_array(current_setting('t.amy')))) $$,
  '42501', null, 'a non-member cannot add an Expense');
update expenses set title = 'hacked';

-- 05: any Member edits and deletes any Expense; every change is logged -------------------
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select results_eq(
  $$ select title from expenses where id = 'eeeeeeee-0000-0000-0000-000000000001' $$,
  array['火鍋'], 'a non-member''s edit did nothing');
update expenses set amount_cents = 12000 where id = 'eeeeeeee-0000-0000-0000-000000000001';
select results_eq(
  $$ select amount_cents from expenses where id = 'eeeeeeee-0000-0000-0000-000000000001' $$,
  array[12000::bigint], 'a Member edits an Expense someone else recorded');
update expenses set deleted_at = now() where id = 'eeeeeeee-0000-0000-0000-000000000001';
select throws_ok($$ delete from expenses $$, '42501', null, 'Expenses are never removed outright');
select results_eq(
  $$ select action, actor_name, (before->>'amount_cents')::int, (after->>'amount_cents')::int
     from change_log where entity_id = 'eeeeeeee-0000-0000-0000-000000000001' order by id $$,
  $$ values ('created', 'Amy', null::int, 10000), ('updated', 'Ben', 10000, 12000),
            ('deleted', 'Ben', 12000, 12000) $$,
  'the history says who did what, with before and after');
select throws_ok(
  $$ insert into change_log (group_id, entity, entity_id, action, actor_name, after)
     values (current_setting('t.group')::uuid, 'expense', gen_random_uuid(), 'created', 'x', '{}') $$,
  '42501', null, 'nobody can write to the history directly');
select throws_ok($$ update change_log set actor_name = 'nobody' $$, '42501', null,
  'the history cannot be altered');
select throws_ok($$ delete from change_log $$, '42501', null, 'the history cannot be removed');

-- 06: Settlements ----------------------------------------------------------------------
select lives_ok($$
  insert into settlements (id, group_id, from_member, to_member, amount_cents, date)
  values ('55555555-0000-0000-0000-000000000001', current_setting('t.group')::uuid,
          current_setting('t.ben')::uuid, current_setting('t.amy')::uuid, 5000, '2026-12-06') $$,
  'a Member records a Settlement');
select throws_ok($$
  insert into settlements (group_id, from_member, to_member, amount_cents, date)
  values (current_setting('t.group')::uuid, current_setting('t.ben')::uuid,
          current_setting('t.ben')::uuid, 5000, '2026-12-06') $$,
  '23514', null, 'a Settlement is between two different Members');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select results_eq('select amount_cents from settlements', array[5000::bigint],
  'the Member who was paid sees the Settlement');
update settlements set amount_cents = 6000;
update settlements set deleted_at = now();
select results_eq(
  $$ select action, actor_name from change_log where entity = 'settlement' order by id $$,
  $$ values ('created', 'Ben'), ('updated', 'Amy'), ('deleted', 'Amy') $$,
  'Settlement changes are logged too');
select throws_ok($$ delete from settlements $$, '42501', null, 'Settlements are never removed outright');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000c"}';
select is_empty('select * from settlements', 'a non-member cannot read Settlements');
select throws_ok($$
  insert into settlements (group_id, from_member, to_member, amount_cents, date)
  values (current_setting('t.group')::uuid, current_setting('t.ben')::uuid,
          current_setting('t.amy')::uuid, 1, '2026-12-06') $$,
  '42501', null, 'a non-member cannot record a Settlement');

-- 08: Attendance and Proposals -----------------------------------------------------------
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select lives_ok($$ select set_attendance('aaaaaaaa-0000-0000-0000-000000000001',
  current_setting('t.ben')::uuid, 'going') $$, 'a Member sets their own Attendance');
select lives_ok($$ select set_attendance('aaaaaaaa-0000-0000-0000-000000000001',
  current_setting('t.ben')::uuid, 'not_going') $$, 'and changes it');
select results_eq('select status from attendance', array['not_going'], 'the latest reply stands');
select throws_ok($$ select set_attendance('aaaaaaaa-0000-0000-0000-000000000001',
  current_setting('t.amy')::uuid, 'going') $$, '42501', null,
  'nobody sets another Member''s Attendance');
select lives_ok($$ insert into members (group_id, name) values (current_setting('t.group')::uuid, 'Dan') $$,
  'a Member adds a Placeholder Member');
select set_config('t.dan', (select id::text from members where name = 'Dan'), true);
select lives_ok($$ select set_attendance('aaaaaaaa-0000-0000-0000-000000000001',
  current_setting('t.dan')::uuid, 'going') $$, 'a Member sets a Placeholder Member''s Attendance');
select lives_ok($$
  insert into proposals (id, group_id, activity_id, title, amount_kind, amount_cents) values
  ('bbbbbbbb-0000-0000-0000-000000000001', current_setting('t.group')::uuid,
   'aaaaaaaa-0000-0000-0000-000000000001', '餐廳 A', 'per_person', 80000),
  ('bbbbbbbb-0000-0000-0000-000000000002', current_setting('t.group')::uuid,
   'aaaaaaaa-0000-0000-0000-000000000001', '餐廳 B', 'total', 150000) $$,
  'any Member opens Proposals, several per Activity');
select throws_ok($$ update proposals set status = 'chosen' $$, '42501', null,
  'a Proposal''s status cannot be set directly');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000c"}';
select is_empty('select * from proposals', 'a non-member cannot read Proposals');
select is_empty('select * from attendance', 'a non-member cannot read Attendance');
select throws_ok($$ select set_attendance('aaaaaaaa-0000-0000-0000-000000000001',
  current_setting('t.dan')::uuid, 'not_going') $$, '42501', null,
  'a non-member cannot set anyone''s Attendance');
select throws_ok($$
  insert into proposals (group_id, activity_id, title, amount_kind, amount_cents)
  values (current_setting('t.group')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001', 'X', 'total', 1) $$,
  '42501', null, 'a non-member cannot open a Proposal');

-- 09: only the Organiser sets the Activity Budget ------------------------------------------
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select throws_ok($$ select set_activity_budget('aaaaaaaa-0000-0000-0000-000000000001', 100) $$,
  '42501', null, 'a Member who is not the Organiser cannot set the Activity Budget');
select throws_ok($$ update activities set budget_cents = 100 $$, '42501', null,
  'nor change it directly');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select lives_ok($$ select set_activity_budget('aaaaaaaa-0000-0000-0000-000000000001', 300000) $$,
  'the Organiser sets the Activity Budget');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select results_eq('select budget_cents from activities', array[300000::bigint],
  'the whole Group sees the Activity Budget');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select set_activity_budget('aaaaaaaa-0000-0000-0000-000000000001', null);
select results_eq('select budget_cents from activities', array[null::bigint],
  'the Organiser removes the Activity Budget');

-- 10: the Chosen Proposal and turning it into an Expense -------------------------------------
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select throws_ok($$ select choose_proposal('bbbbbbbb-0000-0000-0000-000000000001') $$,
  '42501', null, 'a Member who is not the Organiser cannot choose a Proposal');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select choose_proposal('bbbbbbbb-0000-0000-0000-000000000001');
select choose_proposal('bbbbbbbb-0000-0000-0000-000000000002');
select results_eq('select title, status from proposals order by title',
  $$ values ('餐廳 A', 'open'), ('餐廳 B', 'chosen') $$,
  'choosing another Proposal replaces the Chosen Proposal');
select unchoose_proposal('bbbbbbbb-0000-0000-0000-000000000002');
select results_eq($$ select count(*) from proposals where status = 'chosen' $$, array[0::bigint],
  'the Organiser can cancel the choice');
insert into activities (id, group_id, name, organiser_id)
  values ('aaaaaaaa-0000-0000-0000-000000000002', current_setting('t.group')::uuid, '未定日期',
          current_setting('t.amy')::uuid);
insert into proposals (id, group_id, activity_id, title, amount_kind, amount_cents)
  values ('bbbbbbbb-0000-0000-0000-000000000003', current_setting('t.group')::uuid,
          'aaaaaaaa-0000-0000-0000-000000000002', 'C', 'total', 100);
select throws_ok($$ select choose_proposal('bbbbbbbb-0000-0000-0000-000000000003') $$,
  '23514', null, 'an Activity with no date cannot have a Chosen Proposal');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select throws_ok($$
  insert into expenses (group_id, activity_id, proposal_id, title, date, amount_cents, paid_by, split)
  values (current_setting('t.group')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001',
          'bbbbbbbb-0000-0000-0000-000000000001', '餐廳 A', '2026-12-05', 100,
          current_setting('t.ben')::uuid,
          jsonb_build_object('kind', 'equal', 'members', jsonb_build_array(current_setting('t.ben')))) $$,
  '23514', null, 'an open Proposal cannot become an Expense');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select choose_proposal('bbbbbbbb-0000-0000-0000-000000000001');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select lives_ok($$
  insert into expenses (group_id, activity_id, proposal_id, title, date, amount_cents, paid_by, split)
  values (current_setting('t.group')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001',
          'bbbbbbbb-0000-0000-0000-000000000001', '餐廳 A', '2026-12-05', 150000,
          current_setting('t.ben')::uuid,
          jsonb_build_object('kind', 'equal', 'members', jsonb_build_array(current_setting('t.ben')))) $$,
  'any Member turns the Chosen Proposal into an Expense');
select results_eq($$ select status from proposals where title = '餐廳 A' $$, array['converted'],
  'which retires the Proposal');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select throws_ok($$ select choose_proposal('bbbbbbbb-0000-0000-0000-000000000001') $$,
  '23514', null, 'a converted Proposal cannot be chosen again');

-- 07: claiming a Placeholder Member, and leaving ----------------------------------------------
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000c"}';
select results_eq(
  $$ select name from invite_placeholders(current_setting('t.invite')::uuid) $$, array['Dan'],
  'someone holding the invite sees the Placeholder Members they could claim');
select join_group(current_setting('t.invite')::uuid, 'Cat', current_setting('t.dan')::uuid);
select results_eq(
  $$ select id::text, name from members where user_id = '00000000-0000-0000-0000-00000000000c' $$,
  $$ values (current_setting('t.dan'), 'Dan') $$,
  'claiming keeps the same Member, so their accounts carry over');

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select leave_group(current_setting('t.group')::uuid);
select is_empty('select * from groups', 'after leaving, access to the Group is gone at once');
select is_empty('select * from expenses', 'and so is access to its Expenses');
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select results_eq($$ select user_id from members where name = 'Ben' $$, array[null::uuid],
  'whoever left stays on as a Placeholder Member, so their Balance stays');

select * from finish();
rollback;
