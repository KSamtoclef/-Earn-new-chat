-- Earn Chat Stage 3A verification. Read-only; every blocking row must pass.
begin transaction read only;

with checks(check_name, passed, observed, expected, severity) as (
  select 'all Auth users have profiles', count(*)=0, count(*)::text, '0', 'blocking'
  from auth.users u left join public.profiles p on p.id=u.id where p.id is null
  union all
  select 'balances still reconcile to ledger', count(*)=0, count(*)::text, '0', 'blocking'
  from public.profiles p left join (
    select user_id,sum(amount) filter(where status in ('credited','adjustment','refunded')) balance
    from public.earning_ledger group by user_id
  ) l on l.user_id=p.id where p.balance::bigint<>coalesce(l.balance,0)
  union all
  select 'KYC flags match submissions', count(*)=0, count(*)::text, '0', 'blocking'
  from public.profiles p left join public.kyc_submissions k on k.user_id=p.id
  where coalesce(p.kyc_done,false) is distinct from coalesce(k.status='approved',false)
     or coalesce(p.kyc_pending,false) is distinct from coalesce(k.status='pending',false)
  union all
  select 'no duplicate ledger event keys', count(*)=0, count(*)::text, '0', 'blocking'
  from (select user_id,event_key from public.earning_ledger group by user_id,event_key having count(*)>1) d
  union all
  select 'private reward helpers not client executable', count(*)=0, count(*)::text, '0', 'blocking'
  from pg_proc p where p.pronamespace='public'::regnamespace
    and p.proname in ('_earn_chat_credit','_earn_chat_ensure_profile','_earn_chat_prepare_day','_earn_chat_state')
    and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))
  union all
  select 'admin RPCs unavailable to anon', count(*)=0, count(*)::text, '0', 'blocking'
  from pg_proc p where p.pronamespace='public'::regnamespace
    and p.proname in ('admin_review_kyc','admin_review_withdrawal')
    and has_function_privilege('anon',p.oid,'execute')
  union all
  select 'no public profile mutation policy', count(*)=0, count(*)::text, '0', 'blocking'
  from pg_policies where schemaname='public' and tablename='profiles' and cmd<>'SELECT'
  union all
  select 'profile reads are authenticated only', count(*)=1 and bool_and(roles=array['authenticated'::name]),
    format('policies=%s roles=%s',count(*),string_agg(roles::text,',')), 'policies=1 roles={authenticated}', 'blocking'
  from pg_policies where schemaname='public' and tablename='profiles' and cmd='SELECT'
  union all
  select 'Auth bootstrap trigger enabled', count(*)=1 and bool_and(t.tgenabled<>'D'), count(*)::text, '1', 'blocking'
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='auth' and c.relname='users' and t.tgname='earn_chat_bootstrap_user'
)
select severity,check_name,passed,observed,expected from checks
order by case severity when 'blocking' then 0 else 1 end,passed,check_name;

rollback;
