-- Earn Chat Stage 3C: secure daily-platform server API
-- Conversation/progression only. This migration does not issue wallet credits.

begin;

create table if not exists public.earn_chat_dialogue_nodes (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.earn_chat_partners(id) on delete cascade,
  node_key text not null,
  partner_message text not null check (char_length(partner_message) between 1 and 1200),
  quick_replies jsonb not null default '[]',
  default_next_node text,
  is_completion boolean not null default false,
  active boolean not null default true,
  unique(partner_id,node_key),
  check (jsonb_typeof(quick_replies)='array')
);
create index if not exists earn_chat_dialogue_partner_idx
  on public.earn_chat_dialogue_nodes(partner_id,node_key) where active;

create table if not exists public.earn_chat_intent_rules (
  intent_key text primary key,
  patterns text[] not null,
  priority smallint not null default 100,
  active boolean not null default true
);

alter table public.earn_chat_dialogue_nodes enable row level security;
alter table public.earn_chat_intent_rules enable row level security;
create policy "active dialogue readable" on public.earn_chat_dialogue_nodes
  for select to authenticated using(active);
create policy "active intent rules readable" on public.earn_chat_intent_rules
  for select to authenticated using(active);
revoke all on public.earn_chat_dialogue_nodes,public.earn_chat_intent_rules from anon;
revoke insert,update,delete,truncate,trigger,references on
  public.earn_chat_dialogue_nodes,public.earn_chat_intent_rules from authenticated;
grant select on public.earn_chat_dialogue_nodes,public.earn_chat_intent_rules to authenticated;

insert into public.earn_chat_intent_rules(intent_key,patterns,priority) values
 ('travel',array['travel','visit','trip','flight','holiday','city','country'],10),
 ('culture',array['culture','tradition','festival','language','custom','music','dance'],20),
 ('food',array['food','meal','cook','rice','soup','restaurant','eat'],30),
 ('work',array['work','job','business','career','study','school','skill'],40),
 ('advice',array['advice','help','suggest','recommend','should i','decision'],50),
 ('fun',array['fun','funny','laugh','joke','game','weekend'],60),
 ('detail',array['.+'],999)
on conflict(intent_key) do update set patterns=excluded.patterns,priority=excluded.priority,active=true;

with seed(partner_key,node_key,partner_message,quick_replies,default_next_node,is_completion) as (values
 ('maya_travels','opening','Hey! I’m Maya. I plan trips for a living, but the best recommendations always come from locals. What should I experience first in your city?',
  '[{"label":"Try our local food","intent":"food","next_node":"food"},{"label":"Visit a cultural place","intent":"culture","next_node":"culture"},{"label":"Let me plan a fun day","intent":"travel","next_node":"travel"}]'::jsonb,'travel',false),
 ('maya_travels','food','That sounds worth travelling for. I once planned an entire weekend around one tiny family restaurant. What makes your favourite local meal special?',
  '[{"label":"It reminds me of home","intent":"culture","next_node":"culture"},{"label":"The flavour is unforgettable","intent":"food","next_node":"travel"},{"label":"I would take you there","intent":"travel","next_node":"travel"}]'::jsonb,'travel',false),
 ('maya_travels','culture','I love places with a story behind them. I still remember a guide who explained his city through its music instead of a map. What story would your city tell?',
  '[{"label":"A story about resilience","intent":"advice","next_node":"travel"},{"label":"A story full of music","intent":"culture","next_node":"travel"},{"label":"A funny everyday story","intent":"fun","next_node":"travel"}]'::jsonb,'travel',false),
 ('maya_travels','travel','I can picture that day clearly now. You gave me details no travel website could provide. Which place would you personally return to tomorrow?',
  '[{"label":"A peaceful place","intent":"advice","next_node":"complete"},{"label":"Somewhere lively","intent":"fun","next_node":"complete"},{"label":"My favourite food spot","intent":"food","next_node":"complete"}]'::jsonb,'complete',false),
 ('maya_travels','complete','That was a brilliant local tour. I’ll remember your recommendation the next time we chat.','[]'::jsonb,null,true),

 ('daniel_culture','opening','Hello, I’m Daniel. I teach history, but everyday traditions usually teach me more than textbooks. Which tradition where you live deserves more attention?',
  '[{"label":"Our celebrations","intent":"culture","next_node":"culture"},{"label":"The way we welcome people","intent":"food","next_node":"food"},{"label":"Our modern creative scene","intent":"work","next_node":"work"}]'::jsonb,'culture',false),
 ('daniel_culture','culture','That is exactly the kind of living history I enjoy. A small tradition can explain what a community values. How did you first learn it?',
  '[{"label":"From my family","intent":"culture","next_node":"work"},{"label":"From people around me","intent":"detail","next_node":"work"},{"label":"By joining the celebration","intent":"fun","next_node":"work"}]'::jsonb,'work',false),
 ('daniel_culture','food','Welcoming someone with food says a lot without needing a speech. Which meal or gesture would make a visitor feel included?',
  '[{"label":"A shared family meal","intent":"food","next_node":"work"},{"label":"Teaching them a greeting","intent":"culture","next_node":"work"},{"label":"Showing them around","intent":"travel","next_node":"work"}]'::jsonb,'work',false),
 ('daniel_culture','work','Culture keeps changing through people your age, work and creativity. What would you preserve, and what would you happily modernise?',
  '[{"label":"Preserve our values","intent":"culture","next_node":"complete"},{"label":"Modernise opportunities","intent":"work","next_node":"complete"},{"label":"Blend both carefully","intent":"advice","next_node":"complete"}]'::jsonb,'complete',false),
 ('daniel_culture','complete','You explained that thoughtfully. I’ll remember the balance you described between tradition and change.','[]'::jsonb,null,true),

 ('scarlett_music','opening','Hey, Scarlett here! I collect songs for every mood, but today my playlist cannot decide what it wants to be. What kind of energy should I add?',
  '[{"label":"Something upbeat","intent":"fun","next_node":"fun"},{"label":"A cultural classic","intent":"culture","next_node":"culture"},{"label":"A calm evening sound","intent":"advice","next_node":"calm"}]'::jsonb,'fun',false),
 ('scarlett_music','fun','Upbeat wins! I once danced so badly at a small show that the drummer laughed mid-song. When do you usually play energetic music?',
  '[{"label":"When I am working","intent":"work","next_node":"calm"},{"label":"At celebrations","intent":"culture","next_node":"culture"},{"label":"Whenever I need a laugh","intent":"fun","next_node":"calm"}]'::jsonb,'calm',false),
 ('scarlett_music','culture','Music carries culture faster than a suitcase. What detail makes a song feel connected to where you come from?',
  '[{"label":"The rhythm","intent":"culture","next_node":"calm"},{"label":"The language","intent":"detail","next_node":"calm"},{"label":"The memories around it","intent":"advice","next_node":"calm"}]'::jsonb,'calm',false),
 ('scarlett_music','calm','That gives the playlist a real story instead of just noise. What is one mood you want tomorrow’s music to create?',
  '[{"label":"Focused","intent":"work","next_node":"complete"},{"label":"Happy","intent":"fun","next_node":"complete"},{"label":"Peaceful","intent":"advice","next_node":"complete"}]'::jsonb,'complete',false),
 ('scarlett_music','complete','Playlist rescued! I’ll remember the mood you chose when we continue another day.','[]'::jsonb,null,true),

 ('amelia_business','opening','Hi, I’m Amelia. I like practical ideas more than impressive slogans. What useful skill would you most like to improve this year?',
  '[{"label":"Communication","intent":"work","next_node":"work"},{"label":"Making better decisions","intent":"advice","next_node":"advice"},{"label":"Creative problem-solving","intent":"fun","next_node":"ideas"}]'::jsonb,'work',false),
 ('amelia_business','work','Good choice. Skills improve faster when the practice is specific. Where could you use that skill this week?',
  '[{"label":"At school or work","intent":"work","next_node":"ideas"},{"label":"On a personal project","intent":"fun","next_node":"ideas"},{"label":"In everyday conversations","intent":"detail","next_node":"ideas"}]'::jsonb,'ideas',false),
 ('amelia_business','advice','Better decisions often come from defining the real problem first. What kind of decision usually slows you down?',
  '[{"label":"Choosing priorities","intent":"work","next_node":"ideas"},{"label":"Starting something new","intent":"advice","next_node":"ideas"},{"label":"Knowing when to stop","intent":"detail","next_node":"ideas"}]'::jsonb,'ideas',false),
 ('amelia_business','ideas','That can become a simple experiment instead of a huge plan. What is the smallest useful first step you could take?',
  '[{"label":"Write the plan","intent":"work","next_node":"complete"},{"label":"Ask someone for feedback","intent":"advice","next_node":"complete"},{"label":"Try a small version","intent":"fun","next_node":"complete"}]'::jsonb,'complete',false),
 ('amelia_business','complete','That is practical and measurable. I’ll remember the first step you chose when we check your progress.','[]'::jsonb,null,true),

 ('nora_listens','opening','Hi, I’m Nora. I’m good at listening without rushing to fix everything. What part of your day has taken the most energy lately?',
  '[{"label":"Work or study","intent":"work","next_node":"work"},{"label":"A decision I am considering","intent":"advice","next_node":"advice"},{"label":"Just staying organised","intent":"detail","next_node":"routine"}]'::jsonb,'routine',false),
 ('nora_listens','work','That can drain attention even when the task looks small from outside. Which part feels hardest: starting, continuing, or finishing?',
  '[{"label":"Starting","intent":"advice","next_node":"routine"},{"label":"Staying focused","intent":"work","next_node":"routine"},{"label":"Finishing","intent":"detail","next_node":"routine"}]'::jsonb,'routine',false),
 ('nora_listens','advice','You do not need to solve the whole decision at once. What information would make the next step clearer?',
  '[{"label":"A trusted opinion","intent":"advice","next_node":"routine"},{"label":"More time to think","intent":"detail","next_node":"routine"},{"label":"A simple comparison","intent":"work","next_node":"routine"}]'::jsonb,'routine',false),
 ('nora_listens','routine','A small routine can protect your energy better than relying on motivation. What realistic change could make tomorrow easier?',
  '[{"label":"Prepare earlier","intent":"work","next_node":"complete"},{"label":"Remove one distraction","intent":"advice","next_node":"complete"},{"label":"Take a proper break","intent":"detail","next_node":"complete"}]'::jsonb,'complete',false),
 ('nora_listens','complete','That sounds realistic, not overwhelming. I’ll remember the change you chose and ask how it went next time.','[]'::jsonb,null,true),

 ('owen_kitchen','opening','Hey, I’m Owen. Running a restaurant means every day starts with one important question: what would make people happy to eat today? What meal always improves your mood?',
  '[{"label":"A home-cooked favourite","intent":"food","next_node":"food"},{"label":"Something spicy","intent":"fun","next_node":"spice"},{"label":"A meal shared with people","intent":"culture","next_node":"sharing"}]'::jsonb,'food',false),
 ('owen_kitchen','food','Home favourites are powerful because the memory is part of the flavour. Who introduced you to that meal?',
  '[{"label":"Someone in my family","intent":"culture","next_node":"sharing"},{"label":"I discovered it myself","intent":"fun","next_node":"spice"},{"label":"A local cook","intent":"food","next_node":"sharing"}]'::jsonb,'sharing',false),
 ('owen_kitchen','spice','Spice has confidence! I once tested a sauce that made my whole kitchen team suddenly very quiet. What flavour should balance the heat?',
  '[{"label":"Something sweet","intent":"food","next_node":"sharing"},{"label":"Something fresh","intent":"detail","next_node":"sharing"},{"label":"Even more spice","intent":"fun","next_node":"sharing"}]'::jsonb,'sharing',false),
 ('owen_kitchen','sharing','The people around a meal can matter as much as the recipe. If you hosted a small dinner tomorrow, what would make it memorable?',
  '[{"label":"Good conversation","intent":"culture","next_node":"complete"},{"label":"A surprise dish","intent":"food","next_node":"complete"},{"label":"Music and games","intent":"fun","next_node":"complete"}]'::jsonb,'complete',false),
 ('owen_kitchen','complete','Now I am hungry and inspired. I’ll remember your meal choice for our next kitchen conversation.','[]'::jsonb,null,true)
)
insert into public.earn_chat_dialogue_nodes(partner_id,node_key,partner_message,quick_replies,default_next_node,is_completion)
select p.id,s.node_key,s.partner_message,s.quick_replies,s.default_next_node,s.is_completion
from seed s join public.earn_chat_partners p on p.partner_key=s.partner_key
on conflict(partner_id,node_key) do update set partner_message=excluded.partner_message,
 quick_replies=excluded.quick_replies,default_next_node=excluded.default_next_node,
 is_completion=excluded.is_completion,active=true;

create or replace function earn_chat_private.ensure_daily_plan(p_user_id uuid,p_date date)
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_primary uuid; v_optional uuid[]; v_pick integer;
begin
  if p_user_id is null then raise exception 'Authentication required'; end if;
  v_pick := (hashtextextended(p_user_id::text||p_date::text,0) & 2147483647)::integer;
  select id into v_primary from public.earn_chat_goal_templates where active
  order by priority_weight desc,goal_key offset (v_pick % greatest((select count(*) from public.earn_chat_goal_templates where active),1)) limit 1;
  insert into public.earn_chat_daily_goals(user_id,goal_date,template_id,goal_role,target)
  select p_user_id,p_date,g.id,'primary',g.default_target from public.earn_chat_goal_templates g where g.id=v_primary
  on conflict do nothing;
  select array_agg(id) into v_optional from (select id from public.earn_chat_goal_templates
    where active and id<>v_primary order by md5(p_user_id::text||p_date::text||goal_key) limit 2) q;
  insert into public.earn_chat_daily_goals(user_id,goal_date,template_id,goal_role,target)
  select p_user_id,p_date,g.id,'optional',g.default_target from public.earn_chat_goal_templates g where g.id=any(v_optional)
  on conflict do nothing;
  insert into public.earn_chat_daily_tasks(user_id,task_date,definition_id,display_order,status,unlocked_at)
  select p_user_id,p_date,d.id,row_number() over(order by md5(p_user_id::text||p_date::text||d.task_key))::smallint,
    case when d.minimum_level<=coalesce((select level_number from public.earn_chat_user_progression where user_id=p_user_id),1) then 'available' else 'locked' end,
    case when d.minimum_level<=coalesce((select level_number from public.earn_chat_user_progression where user_id=p_user_id),1) then now() end
  from public.earn_chat_task_definitions d where d.active
  order by md5(p_user_id::text||p_date::text||d.task_key) limit 3
  on conflict do nothing;
end; $$;
revoke all on function earn_chat_private.ensure_daily_plan(uuid,date) from public,anon,authenticated;
grant execute on function earn_chat_private.ensure_daily_plan(uuid,date) to service_role;

create or replace function public.earn_chat_get_home_state()
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_date date:=(now() at time zone 'Africa/Lagos')::date; v_result jsonb;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 perform earn_chat_private.ensure_daily_plan(v_uid,v_date);
 select jsonb_build_object(
  'date',v_date,'profile',jsonb_build_object('name',p.full_name,'day',p.day,'balance',p.balance),
  'streak',to_jsonb(s),'progression',jsonb_build_object('level',l.display_name,'level_number',up.level_number,'points',up.progress_points,'next_points',(select points_required from public.earn_chat_level_definitions where level_number=up.level_number+1)),
  'unfinished_conversations',coalesce((select jsonb_agg(x order by x.last_message_at desc nulls last) from (select t.id,t.last_message_at,t.last_message_preview,pa.partner_key,pa.display_name,pa.avatar from public.earn_chat_threads t join public.earn_chat_partners pa on pa.id=t.partner_id where t.user_id=v_uid and t.status in('active','paused') limit 3)x),'[]'::jsonb),
  'goals',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'role',g.goal_role,'title',gt.title,'description',gt.description,'progress',g.progress,'target',g.target,'status',g.status) order by case g.goal_role when 'primary' then 0 else 1 end) from public.earn_chat_daily_goals g join public.earn_chat_goal_templates gt on gt.id=g.template_id where g.user_id=v_uid and g.goal_date=v_date),'[]'::jsonb),
  'tasks',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'title',d.title,'description',d.description,'type',d.task_type,'progress',t.progress,'target',d.target,'status',t.status,'reward',d.reward_descriptor) order by t.display_order) from public.earn_chat_daily_tasks t join public.earn_chat_task_definitions d on d.id=t.definition_id where t.user_id=v_uid and t.task_date=v_date),'[]'::jsonb),
  'partners',coalesce((select jsonb_agg(x order by x.rotation_order) from (select pa.partner_key,pa.display_name,pa.avatar,pa.location,pa.conversation_mood,pa.interests,md5(v_uid::text||v_date::text||pa.partner_key) rotation_order from public.earn_chat_partners pa where pa.active and pa.unlock_level<=up.level_number limit 6)x),'[]'::jsonb)
 ) into v_result from public.profiles p join public.earn_chat_streaks s on s.user_id=p.id join public.earn_chat_user_progression up on up.user_id=p.id join public.earn_chat_level_definitions l on l.level_number=up.level_number where p.id=v_uid;
 return v_result;
end; $$;

create or replace function public.earn_chat_open_conversation(p_partner_key text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_partner public.earn_chat_partners%rowtype; v_thread public.earn_chat_threads%rowtype; v_node public.earn_chat_dialogue_nodes%rowtype;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select * into v_partner from public.earn_chat_partners where partner_key=p_partner_key and active;
 if not found then raise exception 'Partner unavailable'; end if;
 if v_partner.unlock_level>coalesce((select level_number from public.earn_chat_user_progression where user_id=v_uid),1) then raise exception 'Partner is still locked'; end if;
 select * into v_thread from public.earn_chat_threads where user_id=v_uid and partner_id=v_partner.id and status in('active','paused') order by updated_at desc limit 1 for update;
 if not found then
   insert into public.earn_chat_threads(user_id,partner_id,status,current_node_key,last_message_at)
   values(v_uid,v_partner.id,'active','opening',now()) returning * into v_thread;
   select * into v_node from public.earn_chat_dialogue_nodes where partner_id=v_partner.id and node_key='opening' and active;
   insert into public.earn_chat_messages(thread_id,user_id,sender,content,node_key)
   values(v_thread.id,v_uid,'partner',v_node.partner_message,'opening');
 else
   update public.earn_chat_threads set status='active',updated_at=now() where id=v_thread.id returning * into v_thread;
   select * into v_node from public.earn_chat_dialogue_nodes where partner_id=v_partner.id and node_key=v_thread.current_node_key and active;
 end if;
 return jsonb_build_object('thread_id',v_thread.id,'partner',to_jsonb(v_partner)-'biography'-'opening_style'-'rotation_weight',
  'status',v_thread.status,'message_count',v_thread.message_count,'meaningful_message_count',v_thread.meaningful_message_count,
  'messages',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'sender',m.sender,'content',m.content,'quality_label',m.quality_label,'created_at',m.created_at) order by m.created_at,m.id) from public.earn_chat_messages m where m.thread_id=v_thread.id),'[]'::jsonb),
  'suggestions',v_node.quick_replies);
end; $$;

create or replace function public.earn_chat_send_message(p_thread_id uuid,p_content text,p_client_message_id text,p_selected_intent text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_thread public.earn_chat_threads%rowtype; v_node public.earn_chat_dialogue_nodes%rowtype; v_next public.earn_chat_dialogue_nodes%rowtype;
 v_intent text; v_next_key text; v_words integer; v_score integer:=0; v_duplicate boolean; v_meaningful boolean; v_user_message uuid; v_route jsonb; v_date date:=(now() at time zone 'Africa/Lagos')::date;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if char_length(trim(coalesce(p_content,'')))<2 or char_length(p_content)>1200 then raise exception 'Message length is invalid'; end if;
 if p_client_message_id is null or char_length(p_client_message_id)>120 then raise exception 'Client message identifier required'; end if;
 select * into v_thread from public.earn_chat_threads where id=p_thread_id and user_id=v_uid for update;
 if not found or v_thread.status not in('active','paused') then raise exception 'Conversation is unavailable'; end if;
 if exists(select 1 from public.earn_chat_messages where user_id=v_uid and client_message_id=p_client_message_id) then
   return (select jsonb_build_object('duplicate',true,'message_id',id) from public.earn_chat_messages where user_id=v_uid and client_message_id=p_client_message_id);
 end if;
 select * into v_node from public.earn_chat_dialogue_nodes where partner_id=v_thread.partner_id and node_key=v_thread.current_node_key and active;
 if p_selected_intent is not null then
   select q into v_route from jsonb_array_elements(v_node.quick_replies) q where q->>'intent'=p_selected_intent limit 1;
   if v_route is null then raise exception 'Suggested reply no longer matches the latest message'; end if;
   v_intent:=p_selected_intent;
 else
   select intent_key into v_intent from public.earn_chat_intent_rules r where r.active and lower(p_content) ~* any(r.patterns) order by r.priority limit 1;
   v_intent:=coalesce(v_intent,'detail');
   select q into v_route from jsonb_array_elements(v_node.quick_replies) q where q->>'intent'=v_intent limit 1;
 end if;
 v_next_key:=coalesce(v_route->>'next_node',v_node.default_next_node);
 if v_next_key is null then raise exception 'Conversation route is unavailable'; end if;
 v_words:=coalesce(array_length(regexp_split_to_array(trim(p_content),'\s+'),1),0);
 select exists(select 1 from public.earn_chat_messages where user_id=v_uid and sender='user' and lower(trim(content))=lower(trim(p_content)) order by created_at desc limit 1) into v_duplicate;
 v_score:=least(100,(case when v_words>=8 then 35 when v_words>=4 then 25 when v_words>=2 then 10 else 0 end)+(case when v_route is not null or v_intent<>'detail' then 35 else 15 end)+(case when not v_duplicate then 20 else 0 end)+(case when char_length(trim(p_content))>=30 then 10 else 0 end));
 v_meaningful:=v_score>=60 and not v_duplicate;
 insert into public.earn_chat_messages(thread_id,user_id,sender,client_message_id,content,intent_key,node_key,quality_score,quality_label,quality_reasons)
 values(v_thread.id,v_uid,'user',p_client_message_id,trim(p_content),v_intent,v_thread.current_node_key,v_score,case when v_meaningful then 'meaningful' when v_score>=40 then 'good' else 'needs_detail' end,
  jsonb_build_array(case when v_duplicate then 'repeated_text' else 'original_text' end,case when v_words>=4 then 'enough_detail' else 'needs_more_detail' end)) returning id into v_user_message;
 select * into v_next from public.earn_chat_dialogue_nodes where partner_id=v_thread.partner_id and node_key=v_next_key and active;
 if not found then raise exception 'Partner response route is unavailable'; end if;
 insert into public.earn_chat_messages(thread_id,user_id,sender,content,node_key) values(v_thread.id,v_uid,'partner',v_next.partner_message,v_next.node_key);
 update public.earn_chat_threads set current_node_key=v_next.node_key,message_count=message_count+1,
  meaningful_message_count=meaningful_message_count+(case when v_meaningful then 1 else 0 end),last_message_preview=left(v_next.partner_message,160),last_message_at=now(),updated_at=now(),
  status=case when v_next.is_completion then 'completed' else 'active' end,completed_at=case when v_next.is_completion then now() else null end where id=v_thread.id;
 if v_meaningful then
   insert into public.earn_chat_memories(user_id,partner_id,memory_key,memory_value,confidence,source_message_id)
   values(v_uid,v_thread.partner_id,'recent_'+v_intent,left(trim(p_content),500),0.8,v_user_message)
   on conflict(user_id,partner_id,memory_key) do update set memory_value=excluded.memory_value,confidence=excluded.confidence,source_message_id=excluded.source_message_id,updated_at=now();
   update public.earn_chat_user_progression set meaningful_messages=meaningful_messages+1,progress_points=progress_points+2,updated_at=now() where user_id=v_uid;
   update public.earn_chat_streaks set current_streak=case when last_active_date=v_date then current_streak when last_active_date=v_date-1 then current_streak+1 else 1 end,
    longest_streak=greatest(longest_streak,case when last_active_date=v_date then current_streak when last_active_date=v_date-1 then current_streak+1 else 1 end),last_active_date=v_date,updated_at=now() where user_id=v_uid;
   update public.earn_chat_daily_goals g set progress=least(g.target,g.progress+1),status=case when g.progress+1>=g.target then 'completed' else g.status end,completed_at=case when g.progress+1>=g.target then coalesce(g.completed_at,now()) else g.completed_at end
   from public.earn_chat_goal_templates gt where g.template_id=gt.id and g.user_id=v_uid and g.goal_date=v_date and gt.goal_type='meaningful_reply' and g.status='active';
 end if;
 if v_next.is_completion then
   update public.earn_chat_user_progression set completed_conversations=completed_conversations+1,progress_points=progress_points+10,updated_at=now() where user_id=v_uid;
   update public.earn_chat_daily_goals g set progress=least(g.target,g.progress+1),status=case when g.progress+1>=g.target then 'completed' else g.status end,completed_at=case when g.progress+1>=g.target then coalesce(g.completed_at,now()) else g.completed_at end
   from public.earn_chat_goal_templates gt where g.template_id=gt.id and g.user_id=v_uid and g.goal_date=v_date and gt.goal_type='conversation' and g.status='active';
 end if;
 update public.earn_chat_user_progression up set level_number=coalesce((select max(level_number) from public.earn_chat_level_definitions l where l.active and l.points_required<=up.progress_points),1),updated_at=now() where up.user_id=v_uid;
 return jsonb_build_object('duplicate',false,'user_message_id',v_user_message,'quality_score',v_score,'quality_label',case when v_meaningful then 'meaningful' when v_score>=40 then 'good' else 'needs_detail' end,
  'intent',v_intent,'partner_message',jsonb_build_object('content',v_next.partner_message,'node_key',v_next.node_key),'suggestions',v_next.quick_replies,'conversation_completed',v_next.is_completion);
end; $$;

revoke all on function public.earn_chat_get_home_state() from public,anon;
revoke all on function public.earn_chat_open_conversation(text) from public,anon;
revoke all on function public.earn_chat_send_message(uuid,text,text,text) from public,anon;
grant execute on function public.earn_chat_get_home_state() to authenticated;
grant execute on function public.earn_chat_open_conversation(text) to authenticated;
grant execute on function public.earn_chat_send_message(uuid,text,text,text) to authenticated;

commit;
