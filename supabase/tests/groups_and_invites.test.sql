-- Who can read and write Groups and Members, tested as real signed-in users.
-- Run with: npx supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(24);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'amy@rls-test.invalid'),
  ('00000000-0000-0000-0000-00000000000b', 'ben@rls-test.invalid');

-- Amy opens a Group ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select lives_ok($$ select create_group('  飯腳  ', ' Amy ') $$, 'a signed-in user can open a Group');
select results_eq('select name from groups', array['飯腳'], 'the creator sees the Group, name trimmed');
select results_eq(
  'select name, user_id from members',
  $$ values ('Amy', '00000000-0000-0000-0000-00000000000a'::uuid) $$,
  'the creator is its first Member');
select throws_ok($$ select create_group('  ', 'Amy') $$, '23514', null, 'a Group needs a name');
select throws_ok($$ select create_group('X', '') $$, '23514', null, 'a Member needs a name');
select results_eq('select count(*) from groups', array[1::bigint], 'a failed create leaves nothing behind');

-- Ben is not a Member: reads nothing, writes nothing ---------------------------
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}';

select is_empty('select * from groups', 'a non-member cannot read the Group');
select is_empty('select * from members', 'a non-member cannot read its Members');
update groups set name = 'hacked';
select throws_ok(
  $$ insert into groups (name) values ('direct') $$, '42501', null,
  'Groups cannot be inserted directly');
select throws_ok(
  $$ insert into members (group_id, user_id, name)
     select id, '00000000-0000-0000-0000-00000000000b', 'Ben' from groups $$,
  '42501', null, 'nobody can add themselves to a Group without an invite');
select throws_ok($$ delete from groups $$, '42501', null, 'Groups cannot be deleted');
select throws_ok($$ delete from members $$, '42501', null, 'Members cannot be deleted');
select throws_ok(
  $$ select join_group('11111111-1111-1111-1111-111111111111', 'Ben') $$, 'P0002', null,
  'a made-up invite does not work');

-- Amy: the non-member's rename did nothing; hers works -------------------------
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select results_eq('select name from groups', array['飯腳'], 'a non-member cannot rename the Group');
update groups set name = '飯腳們';
select results_eq('select name from groups', array['飯腳們'], 'a Member can rename the Group');
select throws_ok(
  $$ update groups set invite_token = gen_random_uuid() $$, '42501', null,
  'the invite cannot be swapped directly');
select set_config('test.invite', (select invite_token::text from groups), true);

-- Ben follows the invite link ---------------------------------------------------
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}';

select is(
  invited_group_name(current_setting('test.invite')::uuid), '飯腳們',
  'the invite shows which Group it is for before joining');
select lives_ok(
  $$ select join_group(current_setting('test.invite')::uuid, 'Ben') $$,
  'the invite lets a non-member join');
select results_eq('select name from groups', array['飯腳們'], 'after joining, the Group is readable');
select results_eq(
  'select name from members order by created_at, name', array['Amy', 'Ben'],
  'both Members see the full Member list');
select lives_ok(
  $$ select join_group(current_setting('test.invite')::uuid, 'Ben again') $$,
  'following the invite twice is harmless');
select results_eq('select count(*) from members', array[2::bigint], 'and does not add a second Member');

-- A user can belong to several Groups ----------------------------------------------
select create_group('旅行團友', 'Ben');
select results_eq(
  'select name from groups order by name', array['旅行團友', '飯腳們'],
  'a user sees every Group they belong to');

-- Signed out -----------------------------------------------------------------------
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok(
  $$ select create_group('X', 'Y') $$, '42501', null,
  'signed-out callers cannot open Groups');

select * from finish();
rollback;
