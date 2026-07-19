-- Earn Chat Stage 2B: data and security reconciliation
-- Read-only. Run as postgres and export the single result grid as CSV.

begin transaction read only;

with
table_counts as (
  select 'TABLE_COUNT'::text section, 'analytics_events'::text metric,
         count(*)::numeric count_value, '{}'::jsonb details from public.analytics_events
  union all select 'TABLE_COUNT','chat_reward_sessions',count(*)::numeric,'{}'::jsonb from public.chat_reward_sessions
  union all select 'TABLE_COUNT','cte_registrations',count(*)::numeric,'{}'::jsonb from public.cte_registrations
  union all select 'TABLE_COUNT','daily_task_attempts',count(*)::numeric,'{}'::jsonb from public.daily_task_attempts
  union all select 'TABLE_COUNT','earn_chat_settings',count(*)::numeric,'{}'::jsonb from public.earn_chat_settings
  union all select 'TABLE_COUNT','earning_ledger',count(*)::numeric,'{}'::jsonb from public.earning_ledger
  union all select 'TABLE_COUNT','earning_security_flags',count(*)::numeric,'{}'::jsonb from public.earning_security_flags
  union all select 'TABLE_COUNT','kyc_submissions',count(*)::numeric,'{}'::jsonb from public.kyc_submissions
  union all select 'TABLE_COUNT','profiles',count(*)::numeric,'{}'::jsonb from public.profiles
  union all select 'TABLE_COUNT','site_presence',count(*)::numeric,'{}'::jsonb from public.site_presence
  union all select 'TABLE_COUNT','withdrawal_requests',count(*)::numeric,'{}'::jsonb from public.withdrawal_requests
),
identity as (
  select 'IDENTITY'::text section, 'auth_users'::text metric,
         count(*)::numeric count_value, '{}'::jsonb details from auth.users
  union all
  select 'IDENTITY','auth_users_without_profile',count(*)::numeric,
         jsonb_build_object(
           'created_last_24h', count(*) filter (where u.created_at >= now() - interval '24 hours'),
           'created_last_7d', count(*) filter (where u.created_at >= now() - interval '7 days')
         )
  from auth.users u left join public.profiles p on p.id=u.id where p.id is null
  union all
  select 'IDENTITY','profiles_without_auth_user',count(*)::numeric,'{}'::jsonb
  from public.profiles p left join auth.users u on u.id=p.id where u.id is null
),
ledger_by_type as (
  select 'LEDGER_TYPE'::text section, reward_type || ':' || status metric,
         count(*)::numeric count_value,
         jsonb_build_object('amount_total',coalesce(sum(amount),0),'points_total',coalesce(sum(activity_points),0)) details
  from public.earning_ledger group by reward_type,status
),
ledger_integrity as (
  select 'LEDGER_INTEGRITY'::text section, 'duplicate_event_keys'::text metric,
         count(*)::numeric count_value, '{}'::jsonb details
  from (select user_id,event_key from public.earning_ledger group by user_id,event_key having count(*)>1) d
  union all
  select 'LEDGER_INTEGRITY','ledger_users_without_auth',count(*)::numeric,'{}'::jsonb
  from (select distinct l.user_id from public.earning_ledger l left join auth.users u on u.id=l.user_id where u.id is null) d
  union all
  select 'LEDGER_INTEGRITY','ledger_users_without_profile',count(*)::numeric,'{}'::jsonb
  from (select distinct l.user_id from public.earning_ledger l left join public.profiles p on p.id=l.user_id where p.id is null) d
),
ledger_balance as (
  select user_id,
         coalesce(sum(amount) filter (where status in ('credited','adjustment','refunded')),0)::numeric as credit_total,
         coalesce(sum(amount) filter (where status in ('held','paid')),0)::numeric as held_or_paid_total
  from public.earning_ledger group by user_id
),
balance_reconciliation as (
  select 'BALANCE_RECONCILIATION'::text section, 'profile_vs_ledger_raw_difference'::text metric,
         count(*) filter (where p.balance::numeric <> coalesce(l.credit_total,0))::numeric count_value,
         jsonb_build_object(
           'absolute_difference',coalesce(sum(abs(p.balance::numeric-coalesce(l.credit_total,0))) filter (where p.balance::numeric<>coalesce(l.credit_total,0)),0),
           'profile_balance_total',coalesce(sum(p.balance),0),
           'ledger_credit_total',coalesce(sum(l.credit_total),0),
           'held_or_paid_total',coalesce(sum(l.held_or_paid_total),0),
           'note','Diagnostic only: migration must confirm the legacy balance formula before cutover.'
         ) details
  from public.profiles p left join ledger_balance l on l.user_id=p.id
),
reward_sessions as (
  select 'CHAT_SESSION_STATUS'::text section, status metric, count(*)::numeric count_value,
         jsonb_build_object(
           'message_count',coalesce(sum(message_count),0),
           'share_count',coalesce(sum(share_count),0),
           'message_reward',coalesce(sum(message_reward),0),
           'share_reward',coalesce(sum(share_reward),0)
         ) details
  from public.chat_reward_sessions group by status
  union all
  select 'CHAT_SESSION_INTEGRITY','sessions_without_auth',count(*)::numeric,'{}'::jsonb
  from public.chat_reward_sessions s left join auth.users u on u.id=s.user_id where u.id is null
  union all
  select 'CHAT_SESSION_INTEGRITY','sessions_without_profile',count(*)::numeric,'{}'::jsonb
  from public.chat_reward_sessions s left join public.profiles p on p.id=s.user_id where p.id is null
  union all
  select 'CHAT_SESSION_INTEGRITY','multiple_active_sessions_same_day',count(*)::numeric,'{}'::jsonb
  from (select user_id,earning_date from public.chat_reward_sessions where status='active' group by user_id,earning_date having count(*)>1) d
),
task_attempts as (
  select 'TASK_ATTEMPT'::text section, task_type metric, count(*)::numeric count_value,
         jsonb_build_object(
           'claimed',count(*) filter (where claimed_at is not null),
           'started_not_claimed',count(*) filter (where claimed_at is null)
         ) details
  from public.daily_task_attempts group by task_type
  union all
  select 'TASK_INTEGRITY','attempts_without_auth',count(*)::numeric,'{}'::jsonb
  from public.daily_task_attempts t left join auth.users u on u.id=t.user_id where u.id is null
),
kyc as (
  select 'KYC_STATUS'::text section,status metric,count(*)::numeric count_value,'{}'::jsonb details
  from public.kyc_submissions group by status
  union all
  select 'KYC_INTEGRITY','records_without_auth',count(*)::numeric,'{}'::jsonb
  from public.kyc_submissions k left join auth.users u on u.id=k.user_id where u.id is null
  union all
  select 'KYC_INTEGRITY','profile_flag_disagrees',count(*)::numeric,
         jsonb_build_object('definition','approved should map to kyc_done; pending should map to kyc_pending')
  from public.profiles p left join public.kyc_submissions k on k.user_id=p.id
  where (k.status='approved' and coalesce(p.kyc_done,false)=false)
     or (k.status='pending' and coalesce(p.kyc_pending,false)=false)
     or (k.id is null and (coalesce(p.kyc_done,false) or coalesce(p.kyc_pending,false)))
),
withdrawals as (
  select 'WITHDRAWAL_STATUS'::text section,status metric,count(*)::numeric count_value,
         jsonb_build_object('amount_total',coalesce(sum(amount),0),'paid_total',coalesce(sum(paid_amount),0)) details
  from public.withdrawal_requests group by status
  union all
  select 'WITHDRAWAL_INTEGRITY','records_without_auth',count(*)::numeric,'{}'::jsonb
  from public.withdrawal_requests w left join auth.users u on u.id=w.user_id where u.id is null
  union all
  select 'WITHDRAWAL_INTEGRITY','multiple_pending_per_user',count(*)::numeric,'{}'::jsonb
  from (select user_id from public.withdrawal_requests where status='pending' group by user_id having count(*)>1) d
),
profile_state as (
  select 'PROFILE_DAY'::text section,day::text metric,count(*)::numeric count_value,
         jsonb_build_object('balance_total',coalesce(sum(balance),0),'today_earnings_total',coalesce(sum(today_earnings),0)) details
  from public.profiles group by day
  union all
  select 'PROFILE_SECURITY','earning_locked',count(*) filter(where earning_locked)::numeric,
         jsonb_build_object('review_required',count(*) filter(where security_review_required))
  from public.profiles
  union all
  select 'PROFILE_SECURITY','admin_profiles',count(*) filter(where is_admin)::numeric,'{}'::jsonb from public.profiles
),
security_policies as (
  select 'SECURITY_POLICY'::text section,tablename || ':' || policyname metric,
         case when cmd<>'SELECT' or roles && array['public'::name,'anon'::name] then 1 else 0 end::numeric count_value,
         jsonb_build_object('roles',roles,'command',cmd,'using',qual,'with_check',with_check) details
  from pg_policies
  where schemaname='public'
    and (
      (roles && array['public'::name,'anon'::name] and (qual='true' or with_check='true'))
      or (tablename='profiles' and cmd in ('INSERT','UPDATE','DELETE'))
    )
),
sensitive_rpc(name) as (
  values ('_earn_chat_credit'),('_earn_chat_ensure_profile'),('_earn_chat_prepare_day'),
    ('_earn_chat_state'),('admin_review_kyc'),('admin_review_withdrawal'),
    ('claim_chat_message'),('claim_chat_share'),('claim_daily_reward'),
    ('record_daily_share'),('request_withdrawal'),('submit_kyc_request')
),
security_functions as (
  select 'SECURITY_FUNCTION'::text section,p.oid::regprocedure::text metric,
         case when has_function_privilege('anon',p.oid,'EXECUTE') then 1 else 0 end::numeric count_value,
         jsonb_build_object(
           'security_definer',p.prosecdef,
           'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
           'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE'),
           'checks_auth_uid',position('auth.uid()' in lower(pg_get_functiondef(p.oid)))>0,
           'checks_admin',position('is_current_user_admin' in lower(pg_get_functiondef(p.oid)))>0,
           'fixed_search_path',coalesce(array_to_string(p.proconfig,','),'') ilike '%search_path%'
         ) details
  from sensitive_rpc s
  join pg_proc p on p.proname=s.name and p.pronamespace='public'::regnamespace
),
trigger_security as (
  select 'AUTH_TRIGGER'::text section,t.tgname::text metric,1::numeric count_value,
         jsonb_build_object(
           'function',p.oid::regprocedure::text,
           'enabled',t.tgenabled,
           'mentions_email_confirmed_at',position('email_confirmed_at' in lower(pg_get_functiondef(p.oid)))>0,
           'mentions_profiles',position('profiles' in lower(pg_get_functiondef(p.oid)))>0,
           'function_security_definer',p.prosecdef,
           'fixed_search_path',coalesce(array_to_string(p.proconfig,','),'') ilike '%search_path%'
         ) details
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  join pg_proc p on p.oid=t.tgfoid
  where n.nspname='auth' and c.relname='users' and not t.tgisinternal
),
analytics as (
  select 'ANALYTICS_EVENT'::text section,event_name metric,count(*)::numeric count_value,
         jsonb_build_object('latest',max(created_at),'earliest',min(created_at)) details
  from public.analytics_events group by event_name
),
presence as (
  select 'PRESENCE'::text section,'summary'::text metric,count(*)::numeric count_value,
         jsonb_build_object(
           'seen_last_5m',count(*) filter(where last_seen>=now()-interval '5 minutes'),
           'visible_last_5m',count(*) filter(where is_visible and last_seen>=now()-interval '5 minutes'),
           'authenticated_sessions',count(*) filter(where is_authenticated),
           'unique_visitors',count(distinct visitor_id),
           'rows_without_visitor_id',count(*) filter(where visitor_id is null or visitor_id='')
         ) details
  from public.site_presence
)
select section,metric,count_value,details
from (
  select * from table_counts union all select * from identity union all
  select * from ledger_by_type union all select * from ledger_integrity union all
  select * from balance_reconciliation union all select * from reward_sessions union all
  select * from task_attempts union all select * from kyc union all select * from withdrawals union all
  select * from profile_state union all select * from security_policies union all
  select * from security_functions union all select * from trigger_security union all
  select * from analytics union all select * from presence
) audit
order by section,metric;

rollback;
