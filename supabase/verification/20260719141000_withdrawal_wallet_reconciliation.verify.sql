begin read only;

with checks(check_name,passed,observed,expected,severity) as (
 select 'wallet RPC remains authenticated only',
  has_function_privilege('authenticated','public.earn_chat_get_wallet_state()','EXECUTE') and not has_function_privilege('anon','public.earn_chat_get_wallet_state()','EXECUTE'),
  format('authenticated=%s anon=%s',has_function_privilege('authenticated','public.earn_chat_get_wallet_state()','EXECUTE'),has_function_privilege('anon','public.earn_chat_get_wallet_state()','EXECUTE')),
  'authenticated=true anon=false','blocking'
 union all
 select 'wallet RPC includes held and paid withdrawal entries',count(*)=1 and bool_and(p.prosrc ilike '%held%paid%'),format('functions=%s includes_withdrawals=%s',count(*),bool_and(p.prosrc ilike '%held%paid%')),'functions=1 includes_withdrawals=true','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='earn_chat_get_wallet_state'
 union all
 select 'wallet RPC is secure with fixed path',count(*)=1 and bool_and(p.prosecdef) and bool_and(coalesce(p.proconfig,'{}') @> array['search_path=pg_catalog, public']),format('functions=%s secure=%s',count(*),bool_and(p.prosecdef)),'functions=1 secure=true','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='earn_chat_get_wallet_state'
 union all
 select 'withdrawal holds match journey amounts',count(*)=0,count(*)::text,'0','blocking'
 from public.earn_chat_withdrawal_journeys w join public.earning_ledger l on l.id=w.hold_ledger_id
 where l.currency_code<>'USD' or l.status not in('held','paid') or l.amount<>-w.amount_minor
 union all
 select 'legacy NGN balances remain reconciled',count(*)=0,count(*)::text,'0','blocking'
 from public.profiles p where p.balance::bigint<>coalesce((select sum(l.amount) from public.earning_ledger l where l.user_id=p.id and l.currency_code='NGN' and l.status in('credited','adjustment','refunded')),0)
)
select severity,check_name,passed,observed,expected from checks
order by case severity when 'blocking' then 0 else 1 end,passed,check_name;

rollback;
