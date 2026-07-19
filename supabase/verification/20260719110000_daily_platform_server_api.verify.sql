-- Earn Chat Stage 3C verification. Read-only; every blocking row must pass.
begin transaction read only;

with checks(check_name,passed,observed,expected,severity) as (
 select 'dialogue and intent tables exist',count(*)=2,count(*)::text,'2','blocking'
 from information_schema.tables where table_schema='public' and table_name in('earn_chat_dialogue_nodes','earn_chat_intent_rules')
 union all
 select 'dialogue tables have RLS',count(*)=2 and bool_and(c.relrowsecurity),format('tables=%s all_rls=%s',count(*),coalesce(bool_and(c.relrowsecurity),false)),'tables=2 all_rls=true','blocking'
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in('earn_chat_dialogue_nodes','earn_chat_intent_rules')
 union all
 select 'every active partner has a complete dialogue',count(*)=0,count(*)::text,'0','blocking'
 from public.earn_chat_partners p where p.active and (
   (select count(*) from public.earn_chat_dialogue_nodes n where n.partner_id=p.id and n.active)<5
   or not exists(select 1 from public.earn_chat_dialogue_nodes n where n.partner_id=p.id and n.node_key='opening' and n.active)
   or not exists(select 1 from public.earn_chat_dialogue_nodes n where n.partner_id=p.id and n.is_completion and n.active))
 union all
 select 'non-completion nodes provide three matching suggestions',count(*)=0,count(*)::text,'0','blocking'
 from public.earn_chat_dialogue_nodes n where n.active and not n.is_completion and jsonb_array_length(n.quick_replies)<3
 union all
 select 'all configured dialogue routes resolve',count(*)=0,count(*)::text,'0','blocking'
 from public.earn_chat_dialogue_nodes n cross join lateral jsonb_array_elements(n.quick_replies) q
 where n.active and not exists(select 1 from public.earn_chat_dialogue_nodes target where target.partner_id=n.partner_id and target.node_key=q->>'next_node' and target.active)
 union all
 select 'all suggested intents have active rules',count(*)=0,count(*)::text,'0','blocking'
 from (select distinct q->>'intent' intent from public.earn_chat_dialogue_nodes n cross join lateral jsonb_array_elements(n.quick_replies) q where n.active) i
 where not exists(select 1 from public.earn_chat_intent_rules r where r.intent_key=i.intent and r.active)
 union all
 select 'three public daily-platform RPCs exist',count(*)=3,count(*)::text,'3','blocking'
 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('earn_chat_get_home_state','earn_chat_open_conversation','earn_chat_send_message')
 union all
 select 'public RPC privilege boundary',count(*)=3 and bool_and(has_function_privilege('authenticated',p.oid,'execute')) and not bool_or(has_function_privilege('anon',p.oid,'execute')),
   format('functions=%s authenticated=%s anon=%s',count(*),coalesce(bool_and(has_function_privilege('authenticated',p.oid,'execute')),false),coalesce(bool_or(has_function_privilege('anon',p.oid,'execute')),false)),
   'functions=3 authenticated=true anon=false','blocking'
 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('earn_chat_get_home_state','earn_chat_open_conversation','earn_chat_send_message')
 union all
 select 'public RPCs use security definer and fixed search path',count(*)=3 and bool_and(p.prosecdef) and bool_and(coalesce(array_to_string(p.proconfig,','),'') ilike '%search_path%'),
   format('functions=%s secure=%s fixed_path=%s',count(*),coalesce(bool_and(p.prosecdef),false),coalesce(bool_and(coalesce(array_to_string(p.proconfig,','),'') ilike '%search_path%'),false)),
   'functions=3 secure=true fixed_path=true','blocking'
 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('earn_chat_get_home_state','earn_chat_open_conversation','earn_chat_send_message')
 union all
 select 'conversation RPC cannot write wallet',count(*)=0,count(*)::text,'0','blocking'
 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in('earn_chat_open_conversation','earn_chat_send_message')
   and (lower(pg_get_functiondef(p.oid)) like '%earning_ledger%' or lower(pg_get_functiondef(p.oid)) like '%_earn_chat_credit%')
 union all
 select 'private plan helper is not client executable',not has_function_privilege('anon','earn_chat_private.ensure_daily_plan(uuid,date)','execute') and not has_function_privilege('authenticated','earn_chat_private.ensure_daily_plan(uuid,date)','execute'),
   format('anon=%s authenticated=%s',has_function_privilege('anon','earn_chat_private.ensure_daily_plan(uuid,date)','execute'),has_function_privilege('authenticated','earn_chat_private.ensure_daily_plan(uuid,date)','execute')),
   'anon=false authenticated=false','blocking'
 union all
 select 'message client identifiers remain unique',count(*)=0,count(*)::text,'0','blocking'
 from (select user_id,client_message_id from public.earn_chat_messages where client_message_id is not null group by user_id,client_message_id having count(*)>1)d
 union all
 select 'legacy balances remain reconciled',count(*)=0,count(*)::text,'0','blocking'
 from public.profiles p left join (select user_id,sum(amount) filter(where status in('credited','adjustment','refunded')) balance from public.earning_ledger group by user_id)l on l.user_id=p.id
 where p.balance::bigint<>coalesce(l.balance,0)
)
select severity,check_name,passed,observed,expected from checks
order by case severity when 'blocking' then 0 else 1 end,passed,check_name;
rollback;
