-- Earn Chat Stage 2A: current Supabase read-only inventory
-- Safe to run in the Supabase SQL Editor as role postgres.
-- This script creates nothing and changes no permanent or temporary data.

begin transaction read only;

-- 1. Exact identity and known live-table counts.
select 'identity'::text as section, 'auth_users'::text as object_name,
       count(*)::bigint as count_value
from auth.users
union all
select 'public_data', 'profiles', count(*) from public.profiles
union all
select 'public_data', 'analytics_events', count(*) from public.analytics_events
union all
select 'public_data', 'site_presence', count(*) from public.site_presence
union all
select 'public_data', 'withdrawal_requests', count(*) from public.withdrawal_requests
order by section, object_name;

-- 2. Auth/profile compatibility.
select
  (select count(*) from auth.users)::bigint as auth_users,
  (select count(*) from public.profiles)::bigint as profiles,
  (
    select count(*)
    from auth.users u
    left join public.profiles p on p.id = u.id
    where p.id is null
  )::bigint as auth_users_without_profile,
  (
    select count(*)
    from public.profiles p
    left join auth.users u on u.id = p.id
    where u.id is null
  )::bigint as profiles_without_auth_user;

-- 3. Public tables, RLS state, and planner row estimates.
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as force_rls,
  greatest(c.reltuples::bigint, 0) as estimated_rows,
  pg_size_pretty(pg_total_relation_size(c.oid)) as total_size
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
order by c.relname;

-- 4. Public columns and defaults. This reveals the current data contract without reading user values.
select
  table_name,
  ordinal_position,
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default,
  is_identity,
  is_generated
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;

-- 5. Primary, unique, foreign-key, and check constraints.
select
  n.nspname as schema_name,
  c.relname as table_name,
  con.conname as constraint_name,
  case con.contype
    when 'p' then 'primary_key'
    when 'u' then 'unique'
    when 'f' then 'foreign_key'
    when 'c' then 'check'
    when 'x' then 'exclusion'
    else con.contype::text
  end as constraint_type,
  pg_get_constraintdef(con.oid, true) as definition
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
order by c.relname, constraint_type, con.conname;

-- 6. Index coverage and definitions.
select
  schemaname as schema_name,
  tablename as table_name,
  indexname as index_name,
  indexdef as definition
from pg_indexes
where schemaname = 'public'
order by tablename, indexname;

-- 7. RLS policies. Public/anonymous permissive policies require review.
select
  schemaname as schema_name,
  tablename as table_name,
  policyname as policy_name,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
order by tablename, cmd, policyname;

-- 8. Table privileges available to browser-facing roles.
select
  table_name,
  grantee,
  privilege_type,
  is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated', 'PUBLIC')
order by table_name, grantee, privilege_type;

-- 9. Public functions/RPC signatures and privilege boundaries.
select
  p.proname as function_name,
  p.oid::regprocedure::text as function_signature,
  pg_get_function_result(p.oid) as result_type,
  l.lanname as language,
  p.prosecdef as security_definer,
  p.provolatile as volatility,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_can_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_can_execute,
  has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname = 'public'
order by p.proname, p.oid::regprocedure::text;

-- 10. Public-table triggers, including Auth/profile bootstrap dependencies.
select
  event_object_schema as table_schema,
  event_object_table as table_name,
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
from information_schema.triggers
where event_object_schema in ('public', 'auth')
order by event_object_schema, event_object_table, trigger_name, event_manipulation;

-- 11. Storage buckets and privacy state. No object paths or user files are read.
select
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
from storage.buckets
order by id;

-- 12. Known live RPC coverage expected by the archived frontend.
with expected(function_name) as (
  values
    ('ensure_my_profile'),
    ('get_my_earning_state'),
    ('save_my_experience'),
    ('get_my_public_rank'),
    ('get_public_leaderboard'),
    ('get_public_site_stats'),
    ('is_current_user_admin'),
    ('upsert_site_presence'),
    ('mark_site_presence_inactive'),
    ('submit_kyc_request'),
    ('request_withdrawal'),
    ('admin_review_kyc'),
    ('admin_review_withdrawal')
)
select
  e.function_name,
  count(p.oid) as overload_count,
  coalesce(bool_or(p.prosecdef), false) as any_security_definer,
  coalesce(bool_or(has_function_privilege('anon', p.oid, 'EXECUTE')), false) as anon_can_execute,
  coalesce(bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE')), false) as authenticated_can_execute
from expected e
left join pg_proc p
  on p.proname = e.function_name
 and p.pronamespace = 'public'::regnamespace
group by e.function_name
order by e.function_name;

-- 13. High-level data distributions using only non-sensitive status fields.
select 'profiles_by_day'::text as section,
       coalesce(day::text, 'null') as metric,
       count(*)::bigint as count_value
from public.profiles
group by day
union all
select 'profiles_kyc_done', kyc_done::text, count(*)
from public.profiles
group by kyc_done
union all
select 'profiles_kyc_pending', kyc_pending::text, count(*)
from public.profiles
group by kyc_pending
union all
select 'profiles_has_withdrawn', has_withdrawn::text, count(*)
from public.profiles
group by has_withdrawn
union all
select 'withdrawal_status', coalesce(status::text, 'null'), count(*)
from public.withdrawal_requests
group by status
order by section, metric;

-- 14. Balance range audit. No individual balance is returned.
select
  count(*)::bigint as profile_count,
  coalesce(sum(balance), 0)::numeric as combined_balance,
  coalesce(min(balance), 0)::numeric as minimum_balance,
  coalesce(max(balance), 0)::numeric as maximum_balance,
  count(*) filter (where balance < 0)::bigint as negative_balances,
  count(*) filter (where balance >= 70000)::bigint as profiles_at_first_withdrawal_minimum
from public.profiles;

rollback;
