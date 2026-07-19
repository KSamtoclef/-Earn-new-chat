-- Earn Chat Stage 2A: current Supabase read-only inventory
-- Run once in Supabase SQL Editor as postgres, then export the single result grid as CSV.
-- This transaction creates nothing and changes no permanent or temporary data.

begin transaction read only;

with
known_counts as (
  select 'COUNT'::text section, 'auth.users'::text object_name,
         'exact_rows'::text metric, count(*)::numeric count_value,
         '{}'::jsonb details
  from auth.users
  union all select 'COUNT', 'public.profiles', 'exact_rows', count(*)::numeric, '{}'::jsonb from public.profiles
  union all select 'COUNT', 'public.analytics_events', 'exact_rows', count(*)::numeric, '{}'::jsonb from public.analytics_events
  union all select 'COUNT', 'public.site_presence', 'exact_rows', count(*)::numeric, '{}'::jsonb from public.site_presence
  union all select 'COUNT', 'public.withdrawal_requests', 'exact_rows', count(*)::numeric, '{}'::jsonb from public.withdrawal_requests
),
identity_compatibility as (
  select 'IDENTITY'::text section, 'auth_to_profile'::text object_name,
         'auth_users_without_profile'::text metric, count(*)::numeric count_value,
         '{}'::jsonb details
  from auth.users u left join public.profiles p on p.id = u.id where p.id is null
  union all
  select 'IDENTITY', 'profile_to_auth', 'profiles_without_auth_user', count(*)::numeric, '{}'::jsonb
  from public.profiles p left join auth.users u on u.id = p.id where u.id is null
),
table_inventory as (
  select 'TABLE'::text section, 'public.' || c.relname object_name,
         'configuration'::text metric, greatest(c.reltuples::numeric, 0) count_value,
         jsonb_build_object(
           'rls_enabled', c.relrowsecurity,
           'force_rls', c.relforcerowsecurity,
           'estimated_rows', greatest(c.reltuples::bigint, 0),
           'total_size', pg_size_pretty(pg_total_relation_size(c.oid))
         ) details
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p')
),
column_inventory as (
  select 'COLUMN'::text section, 'public.' || table_name object_name,
         column_name::text metric, null::numeric count_value,
         jsonb_build_object(
           'position', ordinal_position,
           'data_type', data_type,
           'udt_name', udt_name,
           'nullable', is_nullable,
           'default', column_default,
           'identity', is_identity,
           'generated', is_generated
         ) details
  from information_schema.columns
  where table_schema = 'public'
),
constraint_inventory as (
  select 'CONSTRAINT'::text section, 'public.' || c.relname object_name,
         con.conname::text metric, null::numeric count_value,
         jsonb_build_object(
           'type', case con.contype when 'p' then 'primary_key' when 'u' then 'unique'
             when 'f' then 'foreign_key' when 'c' then 'check' when 'x' then 'exclusion'
             else con.contype::text end,
           'definition', pg_get_constraintdef(con.oid, true)
         ) details
  from pg_constraint con
  join pg_class c on c.oid = con.conrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
),
index_inventory as (
  select 'INDEX'::text section, 'public.' || tablename object_name,
         indexname::text metric, null::numeric count_value,
         jsonb_build_object('definition', indexdef) details
  from pg_indexes
  where schemaname = 'public'
),
policy_inventory as (
  select 'POLICY'::text section, 'public.' || tablename object_name,
         policyname::text metric, null::numeric count_value,
         jsonb_build_object(
           'permissive', permissive,
           'roles', roles,
           'command', cmd,
           'using', qual,
           'with_check', with_check
         ) details
  from pg_policies
  where schemaname = 'public'
),
grant_inventory as (
  select 'TABLE_GRANT'::text section, 'public.' || table_name object_name,
         grantee || ':' || privilege_type metric, null::numeric count_value,
         jsonb_build_object('grantee', grantee, 'privilege', privilege_type, 'grantable', is_grantable) details
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee in ('anon', 'authenticated', 'PUBLIC')
),
function_inventory as (
  select 'FUNCTION'::text section, p.oid::regprocedure::text object_name,
         p.proname::text metric, null::numeric count_value,
         jsonb_build_object(
           'result', pg_get_function_result(p.oid),
           'language', l.lanname,
           'security_definer', p.prosecdef,
           'volatility', p.provolatile,
           'anon_execute', has_function_privilege('anon', p.oid, 'EXECUTE'),
           'authenticated_execute', has_function_privilege('authenticated', p.oid, 'EXECUTE'),
           'service_role_execute', has_function_privilege('service_role', p.oid, 'EXECUTE')
         ) details
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_language l on l.oid = p.prolang
  where n.nspname = 'public'
),
trigger_inventory as (
  select 'TRIGGER'::text section, event_object_schema || '.' || event_object_table object_name,
         trigger_name::text metric, null::numeric count_value,
         jsonb_build_object(
           'event', event_manipulation,
           'timing', action_timing,
           'statement', action_statement
         ) details
  from information_schema.triggers
  where event_object_schema in ('public', 'auth')
),
bucket_inventory as (
  select 'STORAGE_BUCKET'::text section, id::text object_name,
         'configuration'::text metric, null::numeric count_value,
         jsonb_build_object(
           'name', name,
           'public', public,
           'file_size_limit', file_size_limit,
           'allowed_mime_types', allowed_mime_types
         ) details
  from storage.buckets
),
expected_rpc(function_name) as (
  values ('ensure_my_profile'), ('get_my_earning_state'), ('save_my_experience'),
    ('get_my_public_rank'), ('get_public_leaderboard'), ('get_public_site_stats'),
    ('is_current_user_admin'), ('upsert_site_presence'), ('mark_site_presence_inactive'),
    ('submit_kyc_request'), ('request_withdrawal'), ('admin_review_kyc'),
    ('admin_review_withdrawal')
),
rpc_coverage as (
  select 'EXPECTED_RPC'::text section, e.function_name object_name,
         'coverage'::text metric, count(p.oid)::numeric count_value,
         jsonb_build_object(
           'overloads', count(p.oid),
           'security_definer', coalesce(bool_or(p.prosecdef), false),
           'anon_execute', coalesce(bool_or(has_function_privilege('anon', p.oid, 'EXECUTE')), false),
           'authenticated_execute', coalesce(bool_or(has_function_privilege('authenticated', p.oid, 'EXECUTE')), false)
         ) details
  from expected_rpc e
  left join pg_proc p on p.proname = e.function_name and p.pronamespace = 'public'::regnamespace
  group by e.function_name
),
profile_distributions as (
  select 'PROFILE_STATE'::text section, 'day'::text object_name,
         coalesce(day::text, 'null') metric, count(*)::numeric count_value, '{}'::jsonb details
  from public.profiles group by day
  union all select 'PROFILE_STATE', 'kyc_done', kyc_done::text, count(*)::numeric, '{}'::jsonb from public.profiles group by kyc_done
  union all select 'PROFILE_STATE', 'kyc_pending', kyc_pending::text, count(*)::numeric, '{}'::jsonb from public.profiles group by kyc_pending
  union all select 'PROFILE_STATE', 'has_withdrawn', has_withdrawn::text, count(*)::numeric, '{}'::jsonb from public.profiles group by has_withdrawn
  union all select 'WITHDRAWAL_STATE', 'status', coalesce(status::text, 'null'), count(*)::numeric, '{}'::jsonb from public.withdrawal_requests group by status
),
balance_summary as (
  select 'BALANCE'::text section, 'profiles'::text object_name,
         'summary'::text metric, count(*)::numeric count_value,
         jsonb_build_object(
           'combined_balance', coalesce(sum(balance), 0),
           'minimum_balance', coalesce(min(balance), 0),
           'maximum_balance', coalesce(max(balance), 0),
           'negative_balances', count(*) filter (where balance < 0),
           'at_or_above_70000', count(*) filter (where balance >= 70000)
         ) details
  from public.profiles
)
select section, object_name, metric, count_value, details
from (
  select * from known_counts
  union all select * from identity_compatibility
  union all select * from table_inventory
  union all select * from column_inventory
  union all select * from constraint_inventory
  union all select * from index_inventory
  union all select * from policy_inventory
  union all select * from grant_inventory
  union all select * from function_inventory
  union all select * from trigger_inventory
  union all select * from bucket_inventory
  union all select * from rpc_coverage
  union all select * from profile_distributions
  union all select * from balance_summary
) inventory
order by section, object_name, metric;

rollback;
