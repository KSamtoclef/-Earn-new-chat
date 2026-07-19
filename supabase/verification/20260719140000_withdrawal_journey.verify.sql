-- Earn Chat Stage 6 verification. Read-only and creates no temporary objects.

begin read only;

with checks(check_name,passed,observed,expected,severity) as (
 select 'six canonical payout tables exist',count(*)=6,count(*)::text,'6','blocking'
 from information_schema.tables where table_schema='public' and table_name in(
  'earn_chat_payout_methods','earn_chat_payout_states','earn_chat_withdrawal_journeys',
  'earn_chat_sharing_progress','earn_chat_kyc_cases','earn_chat_kyc_documents')
 union all
 select 'canonical payout tables have RLS',count(*)=6 and bool_and(c.relrowsecurity),format('tables=%s all_rls=%s',count(*),bool_and(c.relrowsecurity)),'tables=6 all_rls=true','blocking'
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in(
  'earn_chat_payout_methods','earn_chat_payout_states','earn_chat_withdrawal_journeys',
  'earn_chat_sharing_progress','earn_chat_kyc_cases','earn_chat_kyc_documents')
 union all
 select 'all Auth users have payout state',count(*)=0,count(*)::text,'0','blocking'
 from auth.users u left join public.earn_chat_payout_states s on s.user_id=u.id where s.user_id is null
 union all
 select 'future profile payout bootstrap trigger enabled',count(*)=1 and bool_and(t.tgenabled<>'D'),format('triggers=%s enabled=%s',count(*),bool_and(t.tgenabled<>'D')),'triggers=1 enabled=true','blocking'
 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relname='profiles' and t.tgname='earn_chat_bootstrap_payout_state' and not t.tgisinternal
 union all
 select 'no client mutations on payout tables',count(*)=0,count(*)::text,'0','blocking'
 from information_schema.role_table_grants where table_schema='public' and table_name in(
  'earn_chat_payout_methods','earn_chat_payout_states','earn_chat_withdrawal_journeys',
  'earn_chat_sharing_progress','earn_chat_kyc_cases','earn_chat_kyc_documents')
 and grantee in('anon','authenticated','PUBLIC') and privilege_type in('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES')
 union all
 select 'no mutation RLS policies on payout tables',count(*)=0,count(*)::text,'0','blocking'
 from pg_policies where schemaname='public' and tablename in(
  'earn_chat_payout_methods','earn_chat_payout_states','earn_chat_withdrawal_journeys',
  'earn_chat_sharing_progress','earn_chat_kyc_cases','earn_chat_kyc_documents') and cmd<>'SELECT'
 union all
 select 'five payout journey RPCs exist',count(*)=5,count(*)::text,'5','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in(
  'earn_chat_get_payout_state','earn_chat_request_usd_withdrawal','earn_chat_begin_required_share',
  'earn_chat_complete_required_share','earn_chat_submit_kyc')
 union all
 select 'payout RPC privilege boundary',count(*)=5 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')) and not bool_or(has_function_privilege('anon',p.oid,'EXECUTE')),
  format('functions=%s authenticated=%s anon=%s',count(*),bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')),bool_or(has_function_privilege('anon',p.oid,'EXECUTE'))),
  'functions=5 authenticated=true anon=false','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in(
  'earn_chat_get_payout_state','earn_chat_request_usd_withdrawal','earn_chat_begin_required_share',
  'earn_chat_complete_required_share','earn_chat_submit_kyc')
 union all
 select 'payout RPCs secure and fixed path',count(*)=5 and bool_and(p.prosecdef) and bool_and(coalesce(p.proconfig,'{}') @> array['search_path=pg_catalog, public']),
  format('functions=%s secure=%s',count(*),bool_and(p.prosecdef)),'functions=5 secure=true','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in(
  'earn_chat_get_payout_state','earn_chat_request_usd_withdrawal','earn_chat_begin_required_share',
  'earn_chat_complete_required_share','earn_chat_submit_kyc')
 union all
 select 'private sponsored implementation is not client executable',
  not has_function_privilege('authenticated','public.earn_chat_get_inline_sponsored_unpaused(uuid)','EXECUTE') and not has_function_privilege('anon','public.earn_chat_get_inline_sponsored_unpaused(uuid)','EXECUTE'),
  format('authenticated=%s anon=%s',has_function_privilege('authenticated','public.earn_chat_get_inline_sponsored_unpaused(uuid)','EXECUTE'),has_function_privilege('anon','public.earn_chat_get_inline_sponsored_unpaused(uuid)','EXECUTE')),
  'authenticated=false anon=false','blocking'
 union all
 select 'withdrawal and KYC enforce adult account holder',count(*)=2 and bool_and(p.prosrc ilike '%18 years%'),format('functions=%s enforce_age=%s',count(*),bool_and(p.prosrc ilike '%18 years%')),'functions=2 enforce_age=true','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('earn_chat_request_usd_withdrawal','earn_chat_submit_kyc')
 union all
 select 'pause flags match journey state',count(*)=0,count(*)::text,'0','blocking'
 from public.earn_chat_payout_states where case
  when journey_state in('withdrawal_required','sharing_required','kyc_required','kyc_pending','correction_required','suspended') then not(earnings_paused and sponsored_rewards_paused)
  else earnings_paused or sponsored_rewards_paused end
 union all
 select 'open withdrawals have a unique ledger hold',count(*)=0,count(*)::text,'0','blocking'
 from public.earn_chat_withdrawal_journeys w left join public.earning_ledger l on l.id=w.hold_ledger_id
  and l.user_id=w.user_id and l.currency_code='USD' and l.reward_type='withdrawal_hold' and l.amount=-w.amount_minor
 where w.status not in('cancelled') and l.id is null
 union all
 select 'KYC document ownership is consistent',count(*)=0,count(*)::text,'0','blocking'
 from public.earn_chat_kyc_documents d left join public.earn_chat_kyc_cases c on c.id=d.case_id and c.user_id=d.user_id where c.id is null
 union all
 select 'private KYC storage bucket',count(*)=1 and bool_and(public=false),format('rows=%s private=%s',count(*),bool_and(public=false)),'rows=1 private=true','blocking'
 from storage.buckets where id='earn-chat-kyc'
 union all
 select 'country payout method catalogue seeded',count(*)=8,count(*)::text,'8','blocking'
 from public.earn_chat_payout_methods where active
 union all
 select 'legacy NGN balances remain reconciled',count(*)=0,count(*)::text,'0','blocking'
 from public.profiles p where p.balance::bigint<>coalesce((select sum(l.amount) from public.earning_ledger l where l.user_id=p.id and l.currency_code='NGN' and l.status in('credited','adjustment','refunded')),0)
)
select severity,check_name,passed,observed,expected from checks
order by case severity when 'blocking' then 0 else 1 end,passed,check_name;

rollback;
