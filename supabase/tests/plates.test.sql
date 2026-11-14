-- An Expense split by plates keeps its plate counts, and they must agree with its amounts.
-- Run with: npx supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(7);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'amy@plates-test.invalid'),
  ('00000000-0000-0000-0000-00000000000b', 'ben@plates-test.invalid');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
select set_config('t.group', create_group('壽司', 'Amy')::text, true);
select set_config('t.amy', my_member_id(current_setting('t.group')::uuid)::text, true);
select set_config('t.invite', (select invite_token::text from groups), true);
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b"}';
select join_group(current_setting('t.invite')::uuid, 'Ben');
select set_config('t.ben', my_member_id(current_setting('t.group')::uuid)::text, true);
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into activities (id, group_id, name, date, organiser_id)
  values ('aaaaaaaa-0000-0000-0000-000000000001', current_setting('t.group')::uuid, 'Sushi',
          '2026-12-05', current_setting('t.amy')::uuid);

-- Amy: 2 red + 1 black = 51. Ben: 1 silver = 17. Total 68.
create temp table t_plates as select jsonb_build_object(
  'types', '[{"kind":"red","name":"","price_cents":1200,"color_index":0},
             {"kind":"silver","name":"","price_cents":1700,"color_index":0},
             {"kind":"black","name":"","price_cents":2700,"color_index":0}]'::jsonb,
  'counts', jsonb_build_object(current_setting('t.amy'), '[2,0,1]'::jsonb,
                               current_setting('t.ben'), '[0,1,0]'::jsonb)) as plates;
grant select on t_plates to authenticated;

select lives_ok($$
  insert into expenses (id, group_id, activity_id, title, date, amount_cents, paid_by, split, plates)
  values ('eeeeeeee-0000-0000-0000-000000000001', current_setting('t.group')::uuid,
          'aaaaaaaa-0000-0000-0000-000000000001', 'Sushi', '2026-12-05', 6800,
          current_setting('t.amy')::uuid,
          jsonb_build_object('kind', 'exact', 'amounts',
            jsonb_build_object(current_setting('t.amy'), 5100, current_setting('t.ben'), 1700)),
          (select plates from t_plates)) $$,
  'an Expense split by plates keeps its plate counts');
select results_eq(
  $$ select (plates->'counts'->current_setting('t.amy'))::text from expenses $$,
  array['[2, 0, 1]'], 'the plate counts come back as saved');

select throws_ok($$
  insert into expenses (group_id, activity_id, title, date, amount_cents, paid_by, split, plates)
  values (current_setting('t.group')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001', 'X',
          '2026-12-05', 6800, current_setting('t.amy')::uuid,
          jsonb_build_object('kind', 'exact', 'amounts',
            jsonb_build_object(current_setting('t.amy'), 5000, current_setting('t.ben'), 1800)),
          (select plates from t_plates)) $$,
  '23514', null, 'plate counts that do not match the amounts are refused');
select throws_ok($$
  insert into expenses (group_id, activity_id, title, date, amount_cents, paid_by, split, plates)
  values (current_setting('t.group')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001', 'X',
          '2026-12-05', 6800, current_setting('t.amy')::uuid,
          jsonb_build_object('kind', 'equal', 'members',
            jsonb_build_array(current_setting('t.amy'), current_setting('t.ben'))),
          (select plates from t_plates)) $$,
  '23514', null, 'plates only go with exact amounts');
select throws_ok($$
  insert into expenses (group_id, activity_id, title, date, amount_cents, paid_by, split, plates)
  values (current_setting('t.group')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001', 'X',
          '2026-12-05', 6800, current_setting('t.amy')::uuid,
          jsonb_build_object('kind', 'exact', 'amounts',
            jsonb_build_object(current_setting('t.amy'), 5100, current_setting('t.ben'), 1700)),
          '{"types":[{"kind":"red","price_cents":-1200}],"counts":{}}') $$,
  '23514', null, 'a plate cannot have a negative price');

update expenses set split = jsonb_build_object('kind', 'exact', 'amounts',
  jsonb_build_object(current_setting('t.amy'), 6800)), plates = null;
select results_eq($$ select plates is null from expenses $$, array[true],
  'editing it into plain exact amounts drops the plates');
select results_eq(
  $$ select (before->'plates'->'counts'->current_setting('t.ben'))::text from change_log
     where action = 'updated' $$,
  array['[0, 1, 0]'], 'the history keeps the plate counts as they were');

select * from finish();
rollback;
