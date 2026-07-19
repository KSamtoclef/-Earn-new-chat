-- Earn Chat Stage 3B verification. Read-only; every blocking row must pass.
begin transaction read only;

with expected_tables(name) as (values
 ('earn_chat_partners'),('earn_chat_topics'),('earn_chat_threads'),('earn_chat_messages'),
 ('earn_chat_memories'),('earn_chat_level_definitions'),('earn_chat_user_progression'),
 ('earn_chat_streaks'),('earn_chat_goal_templates'),('earn_chat_daily_goals'),
 ('earn_chat_task_definitions'),('earn_chat_daily_tasks'),('earn_chat_sponsored_offers'),
 ('earn_chat_sponsored_opportunities')
), checks(check_name,passed,observed,expected,severity) as (
 select 'all canonical daily-platform tables exist',count(*)=14,count(*)::text,'14','blocking'
 from information_schema.tables t join expected_tables e on e.name=t.table_name where t.table_schema='public'
 union all
 select 'all daily-platform tables have RLS',count(*)=14 and bool_and(c.relrowsecurity),
   format('tables=%s all_rls=%s',count(*),coalesce(bool_and(c.relrowsecurity),false)),'tables=14 all_rls=true','blocking'
 from pg_class c join pg_namespace n on n.oid=c.relnamespace join expected_tables e on e.name=c.relname
 where n.nspname='public'
 union all
 select 'no client mutations on daily-platform tables',count(*)=0,count(*)::text,'0','blocking'
 from information_schema.role_table_grants g join expected_tables e on e.name=g.table_name
 where g.table_schema='public' and g.grantee in ('anon','authenticated','PUBLIC')
   and g.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES')
 union all
 select 'no mutation RLS policies',count(*)=0,count(*)::text,'0','blocking'
 from pg_policies p join expected_tables e on e.name=p.tablename
 where p.schemaname='public' and p.cmd<>'SELECT'
 union all
 select 'seeded distinct partner personalities',count(*)>=6 and count(distinct personality_key)=count(*),
   format('active=%s personalities=%s',count(*),count(distinct personality_key)),'active>=6 personalities=active','blocking'
 from public.earn_chat_partners where active
 union all
 select 'six conversation moods represented',count(distinct conversation_mood)=6,
   count(distinct conversation_mood)::text,'6','blocking' from public.earn_chat_partners where active
 union all
 select 'five progression levels configured',count(*)=5 and min(level_number)=1 and max(level_number)=5,
   format('count=%s range=%s-%s',count(*),min(level_number),max(level_number)),'count=5 range=1-5','blocking'
 from public.earn_chat_level_definitions where active
 union all
 select 'goal catalogue supports primary product loop',count(*)=6,count(*)::text,'6','blocking'
 from public.earn_chat_goal_templates where active
 union all
 select 'task catalogue seeded',count(*)=5,count(*)::text,'5','blocking'
 from public.earn_chat_task_definitions where active
 union all
 select 'all Auth users have progression',count(*)=0,count(*)::text,'0','blocking'
 from auth.users u left join public.earn_chat_user_progression p on p.user_id=u.id where p.user_id is null
 union all
 select 'all Auth users have streak state',count(*)=0,count(*)::text,'0','blocking'
 from auth.users u left join public.earn_chat_streaks s on s.user_id=u.id where s.user_id is null
 union all
 select 'daily-platform bootstrap trigger enabled',count(*)=1 and bool_and(t.tgenabled<>'D'),count(*)::text,'1','blocking'
 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='auth' and c.relname='users' and t.tgname='earn_chat_bootstrap_daily_platform'
 union all
 select 'legacy balances remain reconciled',count(*)=0,count(*)::text,'0','blocking'
 from public.profiles p left join (
   select user_id,sum(amount) filter(where status in ('credited','adjustment','refunded')) balance
   from public.earning_ledger group by user_id
 ) l on l.user_id=p.id where p.balance::bigint<>coalesce(l.balance,0)
 union all
 select 'conversation client ids are idempotent',count(*)=0,count(*)::text,'0','blocking'
 from (select user_id,client_message_id from public.earn_chat_messages where client_message_id is not null
       group by user_id,client_message_id having count(*)>1) d
 union all
 select 'sponsored opportunity keys are idempotent',count(*)=0,count(*)::text,'0','blocking'
 from (select user_id,idempotency_key from public.earn_chat_sponsored_opportunities
       group by user_id,idempotency_key having count(*)>1) d
)
select severity,check_name,passed,observed,expected from checks
order by case severity when 'blocking' then 0 else 1 end,passed,check_name;
rollback;
