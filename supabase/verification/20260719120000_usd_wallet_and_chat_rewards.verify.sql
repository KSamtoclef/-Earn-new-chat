-- Earn Chat Stage 5 USD wallet verification. Read-only; all blocking rows must pass.
begin transaction read only;
with checks(check_name,passed,observed,expected,severity) as (
 select 'USD settings match approved amounts',signup_bonus_minor=500 and meaningful_reply_minor=200 and standard_daily_cap_minor=3000 and returning_daily_cap_minor=4000 and minimum_withdrawal_minor=15000 and first_cycle_maximum_minor=30000,
  format('signup=%s reply=%s caps=%s/%s minimum=%s maximum=%s',signup_bonus_minor,meaningful_reply_minor,standard_daily_cap_minor,returning_daily_cap_minor,minimum_withdrawal_minor,first_cycle_maximum_minor),
  'signup=500 reply=200 caps=3000/4000 minimum=15000 maximum=30000','blocking' from public.earn_chat_currency_settings where id=1
 union all
 select 'all historical ledger rows remain NGN',count(*)=0,count(*)::text,'0','blocking' from public.earning_ledger where event_key not like 'usd:%' and currency_code<>'NGN'
 union all
 select 'USD event keys use USD currency',count(*)=0,count(*)::text,'0','blocking' from public.earning_ledger where event_key like 'usd:%' and currency_code<>'USD'
 union all
 select 'legacy balances remain reconciled using NGN only',count(*)=0,count(*)::text,'0','blocking'
 from public.profiles p left join (select user_id,sum(amount) filter(where status in('credited','adjustment','refunded')) balance from public.earning_ledger where currency_code='NGN' group by user_id)l on l.user_id=p.id
 where p.balance::bigint<>coalesce(l.balance,0)
 union all
 select 'USD source entries are idempotent',count(*)=0,count(*)::text,'0','blocking' from (select user_id,currency_code,source_type,source_id from public.earning_ledger where source_type is not null and source_id is not null group by user_id,currency_code,source_type,source_id having count(*)>1)d
 union all
 select 'wallet writers are not client executable',count(*)=0,count(*)::text,'0','blocking' from pg_proc p where p.pronamespace='earn_chat_private'::regnamespace and p.proname in('append_usd_entry','credit_meaningful_chat_message') and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))
 union all
 select 'wallet RPC boundary',count(*)=2 and bool_and(has_function_privilege('authenticated',p.oid,'execute')) and not bool_or(has_function_privilege('anon',p.oid,'execute')),
  format('functions=%s authenticated=%s anon=%s',count(*),coalesce(bool_and(has_function_privilege('authenticated',p.oid,'execute')),false),coalesce(bool_or(has_function_privilege('anon',p.oid,'execute')),false)),
  'functions=2 authenticated=true anon=false','blocking' from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('earn_chat_get_wallet_state','earn_chat_set_country')
 union all
 select 'meaningful-message trigger enabled',count(*)=1 and bool_and(t.tgenabled<>'D'),count(*)::text,'1','blocking'
 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='earn_chat_messages' and t.tgname='earn_chat_credit_meaningful_message'
 union all
 select 'currency settings cannot be mutated by clients',count(*)=0,count(*)::text,'0','blocking'
 from information_schema.role_table_grants where table_schema='public' and table_name='earn_chat_currency_settings' and grantee in('anon','authenticated','PUBLIC') and privilege_type in('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES')
)
select severity,check_name,passed,observed,expected from checks order by case severity when 'blocking' then 0 else 1 end,passed,check_name;
rollback;
