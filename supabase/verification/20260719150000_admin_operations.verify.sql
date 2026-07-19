begin read only;

with checks(check_name,passed,observed,expected,severity) as (
 select 'canonical admin audit table exists',count(*)=1,count(*)::text,'1','blocking'
 from information_schema.tables where table_schema='public' and table_name='earn_chat_admin_audit_log'
 union all
 select 'admin audit table has RLS',count(*)=1 and bool_and(c.relrowsecurity),format('tables=%s rls=%s',count(*),bool_and(c.relrowsecurity)),'tables=1 rls=true','blocking'
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='earn_chat_admin_audit_log'
 union all
 select 'clients cannot mutate audit log',count(*)=0,count(*)::text,'0','blocking'
 from information_schema.role_table_grants where table_schema='public' and table_name='earn_chat_admin_audit_log'
  and grantee in('anon','authenticated','PUBLIC') and privilege_type in('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES')
 union all
 select 'five canonical admin RPCs exist',count(*)=5,count(*)::text,'5','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in(
  'earn_chat_admin_overview','earn_chat_admin_page','earn_chat_admin_review_kyc','earn_chat_admin_review_withdrawal','earn_chat_admin_save_offer')
 union all
 select 'admin RPC privilege boundary',count(*)=5 and bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')) and not bool_or(has_function_privilege('anon',p.oid,'EXECUTE')),
  format('functions=%s authenticated=%s anon=%s',count(*),bool_and(has_function_privilege('authenticated',p.oid,'EXECUTE')),bool_or(has_function_privilege('anon',p.oid,'EXECUTE'))),
  'functions=5 authenticated=true anon=false','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in(
  'earn_chat_admin_overview','earn_chat_admin_page','earn_chat_admin_review_kyc','earn_chat_admin_review_withdrawal','earn_chat_admin_save_offer')
 union all
 select 'admin RPCs secure with fixed path',count(*)=5 and bool_and(p.prosecdef) and bool_and(coalesce(p.proconfig,'{}') @> array['search_path=pg_catalog, public']),
  format('functions=%s secure=%s fixed=%s',count(*),bool_and(p.prosecdef),bool_and(coalesce(p.proconfig,'{}') @> array['search_path=pg_catalog, public'])),
  'functions=5 secure=true fixed=true','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in(
  'earn_chat_admin_overview','earn_chat_admin_page','earn_chat_admin_review_kyc','earn_chat_admin_review_withdrawal','earn_chat_admin_save_offer')
 union all
 select 'every admin RPC checks admin role',count(*)=5 and bool_and(p.prosrc ilike '%is_current_user_admin%'),format('functions=%s checked=%s',count(*),bool_and(p.prosrc ilike '%is_current_user_admin%')),'functions=5 checked=true','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in(
  'earn_chat_admin_overview','earn_chat_admin_page','earn_chat_admin_review_kyc','earn_chat_admin_review_withdrawal','earn_chat_admin_save_offer')
 union all
 select 'private audit writer not client executable',
  not has_function_privilege('authenticated','earn_chat_private.write_admin_audit(text,text,uuid,jsonb,jsonb,jsonb)','EXECUTE') and not has_function_privilege('anon','earn_chat_private.write_admin_audit(text,text,uuid,jsonb,jsonb,jsonb)','EXECUTE'),
  format('authenticated=%s anon=%s',has_function_privilege('authenticated','earn_chat_private.write_admin_audit(text,text,uuid,jsonb,jsonb,jsonb)','EXECUTE'),has_function_privilege('anon','earn_chat_private.write_admin_audit(text,text,uuid,jsonb,jsonb,jsonb)','EXECUTE')),
  'authenticated=false anon=false','blocking'
 union all
 select 'admin pagination is capped',count(*)=1 and bool_and(p.prosrc ilike '%least%100%'),format('functions=%s capped=%s',count(*),bool_and(p.prosrc ilike '%least%100%')),'functions=1 capped=true','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='earn_chat_admin_page'
 union all
 select 'offer writer requires HTTPS',count(*)=1 and bool_and(p.prosrc ilike '%https://%'),format('functions=%s https=%s',count(*),bool_and(p.prosrc ilike '%https://%')),'functions=1 https=true','blocking'
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='earn_chat_admin_save_offer'
 union all
 select 'audit rows reference real admins',count(*)=0,count(*)::text,'0','blocking'
 from public.earn_chat_admin_audit_log a left join public.profiles p on p.id=a.admin_user_id and p.is_admin where p.id is null
 union all
 select 'withdrawal holds remain reconciled',count(*)=0,count(*)::text,'0','blocking'
 from public.earn_chat_withdrawal_journeys w join public.earning_ledger l on l.id=w.hold_ledger_id
 where l.currency_code<>'USD' or l.amount<>-w.amount_minor
 union all
 select 'legacy NGN balances remain reconciled',count(*)=0,count(*)::text,'0','blocking'
 from public.profiles p where p.balance::bigint<>coalesce((select sum(l.amount) from public.earning_ledger l where l.user_id=p.id and l.currency_code='NGN' and l.status in('credited','adjustment','refunded')),0)
)
select severity,check_name,passed,observed,expected from checks
order by case severity when 'blocking' then 0 else 1 end,passed,check_name;

rollback;
