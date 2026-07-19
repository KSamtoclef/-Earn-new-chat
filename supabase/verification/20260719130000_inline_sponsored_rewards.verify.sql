-- Earn Chat Stage 5B verification. Read-only and creates no temporary table.

begin read only;

with checks(check_name,passed,observed,expected,severity) as (
  select 'five sponsored lifecycle RPCs exist',count(*)=5,count(*)::text,'5','blocking'
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in(
    'earn_chat_get_inline_sponsored','earn_chat_record_sponsored_impression',
    'earn_chat_begin_sponsored','earn_chat_record_sponsored_return','earn_chat_verify_sponsored'
  )
  union all
  select 'sponsored RPC privilege boundary',
    count(*)=5 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE'))
      and not bool_or(has_function_privilege('anon',p.oid,'EXECUTE')),
    format('functions=%s authenticated=%s anon=%s',count(*),bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')),bool_or(has_function_privilege('anon',p.oid,'EXECUTE'))),
    'functions=5 authenticated=true anon=false','blocking'
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in(
    'earn_chat_get_inline_sponsored','earn_chat_record_sponsored_impression',
    'earn_chat_begin_sponsored','earn_chat_record_sponsored_return','earn_chat_verify_sponsored'
  )
  union all
  select 'sponsored RPCs are security definer with fixed path',
    count(*)=5 and bool_and(p.prosecdef) and bool_and(coalesce(p.proconfig,'{}') @> array['search_path=pg_catalog, public']),
    format('functions=%s secure=%s',count(*),bool_and(p.prosecdef)),
    'functions=5 secure=true','blocking'
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in(
    'earn_chat_get_inline_sponsored','earn_chat_record_sponsored_impression',
    'earn_chat_begin_sponsored','earn_chat_record_sponsored_return','earn_chat_verify_sponsored'
  )
  union all
  select 'offer rewards use non-negative USD minor units',count(*)=0,count(*)::text,'0','blocking'
  from public.earn_chat_sponsored_offers where reward_minor<0
  union all
  select 'opportunity idempotency has no duplicates',count(*)=0,count(*)::text,'0','blocking'
  from (
    select user_id,idempotency_key from public.earn_chat_sponsored_opportunities
    group by user_id,idempotency_key having count(*)>1
  ) d
  union all
  select 'one opportunity per thread offer and day',count(*)=0,count(*)::text,'0','blocking'
  from (
    select user_id,thread_id,offer_id,opportunity_date
    from public.earn_chat_sponsored_opportunities where thread_id is not null
    group by user_id,thread_id,offer_id,opportunity_date having count(*)>1
  ) d
  union all
  select 'credited opportunities have one USD ledger source',count(*)=0,count(*)::text,'0','blocking'
  from public.earn_chat_sponsored_opportunities o
  left join public.earning_ledger l on l.id=o.credited_ledger_id
    and l.user_id=o.user_id and l.currency_code='USD'
    and l.source_type='earn_chat_sponsored_opportunity' and l.source_id=o.id
  where o.status='credited' and l.id is null
  union all
  select 'sponsored wallet sources are unique',count(*)=0,count(*)::text,'0','blocking'
  from (
    select user_id,source_id from public.earning_ledger
    where currency_code='USD' and source_type='earn_chat_sponsored_opportunity'
    group by user_id,source_id having count(*)>1
  ) d
  union all
  select 'legacy NGN balances remain reconciled',count(*)=0,count(*)::text,'0','blocking'
  from public.profiles p
  where p.balance::bigint<>coalesce((
    select sum(l.amount) from public.earning_ledger l
    where l.user_id=p.id and l.currency_code='NGN'
      and l.status in('credited','adjustment','refunded')
  ),0)
)
select severity,check_name,passed,observed,expected
from checks
order by case severity when 'blocking' then 0 else 1 end,passed,check_name;

rollback;
