-- Earn Chat Stage 3B: daily-use platform foundation
-- Non-financial progression, conversation continuity, goals, tasks and sponsored opportunities.

begin;

create table if not exists public.earn_chat_partners (
  id uuid primary key default gen_random_uuid(),
  partner_key text not null unique check (partner_key ~ '^[a-z0-9_]{3,40}$'),
  display_name text not null,
  avatar text not null,
  country_code text not null check (char_length(country_code)=2),
  location text not null,
  personality_key text not null,
  conversation_mood text not null check (conversation_mood in ('friendly','funny','professional','advice','culture','travel')),
  interests text[] not null default '{}',
  biography text not null,
  opening_style text not null,
  unlock_level smallint not null default 1 check (unlock_level between 1 and 5),
  rotation_weight smallint not null default 100 check (rotation_weight>0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.earn_chat_topics (
  id uuid primary key default gen_random_uuid(),
  topic_key text not null unique,
  title text not null,
  mood text not null,
  prompt_context text not null,
  active_from date,
  active_until date,
  rotation_weight smallint not null default 100 check (rotation_weight>0),
  active boolean not null default true
);

create table if not exists public.earn_chat_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references public.earn_chat_partners(id),
  topic_id uuid references public.earn_chat_topics(id),
  status text not null default 'active' check (status in ('active','completed','paused','archived')),
  current_node_key text not null default 'opening',
  message_count integer not null default 0 check (message_count>=0),
  meaningful_message_count integer not null default 0 check (meaningful_message_count>=0),
  completion_target integer not null default 8 check (completion_target between 3 and 30),
  last_message_preview text,
  last_message_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists earn_chat_one_open_thread_per_partner
  on public.earn_chat_threads(user_id,partner_id) where status in ('active','paused');
create index if not exists earn_chat_threads_resume_idx
  on public.earn_chat_threads(user_id,status,last_message_at desc nulls last);

create table if not exists public.earn_chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.earn_chat_threads(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  sender text not null check (sender in ('user','partner','system')),
  client_message_id text,
  content text not null check (char_length(content) between 1 and 1200),
  intent_key text,
  node_key text,
  quality_score smallint check (quality_score between 0 and 100),
  quality_label text check (quality_label is null or quality_label in ('needs_detail','good','meaningful')),
  quality_reasons jsonb not null default '[]',
  reaction text,
  created_at timestamptz not null default now()
);
create unique index if not exists earn_chat_message_client_key
  on public.earn_chat_messages(user_id,client_message_id) where client_message_id is not null;
create index if not exists earn_chat_messages_thread_idx
  on public.earn_chat_messages(thread_id,created_at,id);

create table if not exists public.earn_chat_memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references public.earn_chat_partners(id),
  memory_key text not null,
  memory_value text not null check (char_length(memory_value)<=500),
  confidence numeric(4,3) not null default 1 check (confidence between 0 and 1),
  source_message_id uuid references public.earn_chat_messages(id) on delete set null,
  last_used_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(user_id,partner_id,memory_key)
);
create index if not exists earn_chat_memories_context_idx
  on public.earn_chat_memories(user_id,partner_id,updated_at desc);

create table if not exists public.earn_chat_level_definitions (
  level_number smallint primary key check (level_number between 1 and 5),
  level_key text not null unique,
  display_name text not null,
  points_required bigint not null check (points_required>=0),
  unlocks jsonb not null default '{}',
  active boolean not null default true
);

create table if not exists public.earn_chat_user_progression (
  user_id uuid primary key references auth.users(id) on delete cascade,
  level_number smallint not null default 1 references public.earn_chat_level_definitions(level_number),
  progress_points bigint not null default 0 check (progress_points>=0),
  meaningful_messages bigint not null default 0 check (meaningful_messages>=0),
  completed_conversations bigint not null default 0 check (completed_conversations>=0),
  completed_tasks bigint not null default 0 check (completed_tasks>=0),
  profile_completion smallint not null default 0 check (profile_completion between 0 and 100),
  updated_at timestamptz not null default now()
);

create table if not exists public.earn_chat_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak integer not null default 0 check (current_streak>=0),
  longest_streak integer not null default 0 check (longest_streak>=0),
  last_active_date date,
  protected_until date,
  milestone_claims jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

create table if not exists public.earn_chat_goal_templates (
  id uuid primary key default gen_random_uuid(),
  goal_key text not null unique,
  title text not null,
  description text not null,
  goal_type text not null check (goal_type in ('conversation','meaningful_reply','new_partner','return_chat','sponsored','daily_bonus')),
  default_target integer not null check (default_target>0),
  priority_weight smallint not null default 100 check (priority_weight>0),
  reward_descriptor jsonb not null default '{}',
  active boolean not null default true
);

create table if not exists public.earn_chat_daily_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  goal_date date not null,
  template_id uuid not null references public.earn_chat_goal_templates(id),
  goal_role text not null check (goal_role in ('primary','optional')),
  target integer not null check (target>0),
  progress integer not null default 0 check (progress>=0),
  status text not null default 'active' check (status in ('active','completed','expired')),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(user_id,goal_date,template_id)
);
create unique index if not exists earn_chat_one_primary_goal_daily
  on public.earn_chat_daily_goals(user_id,goal_date) where goal_role='primary';
create index if not exists earn_chat_daily_goals_home_idx
  on public.earn_chat_daily_goals(user_id,goal_date,status);

create table if not exists public.earn_chat_task_definitions (
  id uuid primary key default gen_random_uuid(),
  task_key text not null unique,
  title text not null,
  description text not null,
  task_type text not null check (task_type in ('chat','return','sponsored','profile','referral','bonus')),
  target integer not null default 1 check (target>0),
  reward_descriptor jsonb not null default '{}',
  minimum_level smallint not null default 1 check (minimum_level between 1 and 5),
  active boolean not null default true
);

create table if not exists public.earn_chat_daily_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_date date not null,
  definition_id uuid not null references public.earn_chat_task_definitions(id),
  display_order smallint not null check (display_order between 1 and 20),
  progress integer not null default 0 check (progress>=0),
  status text not null default 'available' check (status in ('locked','available','started','completed','expired')),
  unlocked_at timestamptz,
  completed_at timestamptz,
  metadata jsonb not null default '{}',
  unique(user_id,task_date,definition_id)
);
create index if not exists earn_chat_daily_tasks_home_idx
  on public.earn_chat_daily_tasks(user_id,task_date,status,display_order);

create table if not exists public.earn_chat_sponsored_offers (
  id uuid primary key default gen_random_uuid(),
  offer_key text not null unique,
  title text not null,
  description text not null,
  destination_url text not null,
  placement text not null check (placement in ('inline_chat','daily_task','post_chat')),
  minimum_meaningful_replies integer not null default 3 check (minimum_meaningful_replies>=0),
  minimum_seconds_away integer not null default 15 check (minimum_seconds_away between 0 and 3600),
  reward_descriptor jsonb not null default '{}',
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.earn_chat_sponsored_opportunities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  offer_id uuid not null references public.earn_chat_sponsored_offers(id),
  thread_id uuid references public.earn_chat_threads(id) on delete set null,
  opportunity_date date not null,
  status text not null default 'available' check (status in ('available','impressed','clicked','returned','verified','credited','expired')),
  idempotency_key text not null,
  impressed_at timestamptz,
  clicked_at timestamptz,
  returned_at timestamptz,
  verified_at timestamptz,
  credited_ledger_id uuid references public.earning_ledger(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(user_id,idempotency_key)
);
create index if not exists earn_chat_sponsored_user_idx
  on public.earn_chat_sponsored_opportunities(user_id,opportunity_date,status);

insert into public.earn_chat_level_definitions(level_number,level_key,display_name,points_required,unlocks)
values
  (1,'new_member','New Member',0,'{"daily_goals":true}'::jsonb),
  (2,'active_chatter','Active Chatter',100,'{"partner_slots":4}'::jsonb),
  (3,'top_conversationalist','Top Conversationalist',350,'{"partner_slots":6,"high_value_tasks":true}'::jsonb),
  (4,'verified_member','Verified Member',750,'{"verified_badge":true,"themes":["emerald"]}'::jsonb),
  (5,'elite_member','Elite Member',1500,'{"elite_badge":true,"exclusive_topics":true}'::jsonb)
on conflict(level_number) do update set display_name=excluded.display_name,points_required=excluded.points_required,unlocks=excluded.unlocks;

insert into public.earn_chat_partners
  (partner_key,display_name,avatar,country_code,location,personality_key,conversation_mood,interests,biography,opening_style,unlock_level)
values
  ('maya_travels','Maya R.','🧳','CA','Toronto, Canada','curious_explorer','travel',array['travel','food','cities'],'A curious travel planner who remembers places users want to visit.','Warm questions and short travel stories.',1),
  ('daniel_culture','Daniel O.','📚','GB','Edinburgh, UK','thoughtful_historian','culture',array['history','culture','music'],'A thoughtful lecturer who connects history with everyday culture.','Reflective but concise.',1),
  ('scarlett_music','Scarlett T.','🎵','US','Nashville, USA','playful_music_fan','funny',array['music','Afrobeats','events'],'An energetic music fan who enjoys playful comparisons and reactions.','Casual, funny and energetic.',1),
  ('amelia_business','Amelia D.','💼','AU','Brisbane, Australia','practical_builder','professional',array['business','careers','ideas'],'A practical entrepreneur who asks clear questions and gives grounded encouragement.','Direct and professional.',2),
  ('nora_listens','Nora J.','🌿','GB','Liverpool, UK','warm_listener','advice',array['wellbeing','work','daily life'],'A patient listener focused on constructive everyday advice.','Warm, calm and non-judgmental.',2),
  ('owen_kitchen','Owen T.','🍲','CA','Toronto, Canada','friendly_foodie','friendly',array['food','basketball','restaurants'],'A friendly restaurant owner who remembers favourite meals.','Friendly questions and mini-stories.',1)
on conflict(partner_key) do update set display_name=excluded.display_name,biography=excluded.biography,opening_style=excluded.opening_style,active=true;

insert into public.earn_chat_topics(topic_key,title,mood,prompt_context,rotation_weight)
values
 ('today_city','Life in your city','friendly','Discuss one specific detail about everyday life in the user’s city.',100),
 ('culture_swap','Culture swap','culture','Compare a custom, celebration, meal or expression respectfully.',100),
 ('future_trip','Plan a future trip','travel','Build a small imaginary itinerary using details the user shares.',90),
 ('music_story','A song and a memory','funny','Discuss music preferences without requesting copyrighted lyrics.',80),
 ('work_ideas','Work and useful skills','professional','Discuss practical skills, goals and learning experiences.',70)
on conflict(topic_key) do update set title=excluded.title,prompt_context=excluded.prompt_context,active=true;

insert into public.earn_chat_goal_templates(goal_key,title,description,goal_type,default_target,priority_weight,reward_descriptor)
values
 ('complete_conversations','Complete meaningful conversations','Reach the natural completion point in two conversations.','conversation',2,120,'{"progress_points":30}'::jsonb),
 ('meaningful_replies','Send meaningful replies','Reply with relevant detail instead of repeated or random text.','meaningful_reply',5,110,'{"progress_points":20}'::jsonb),
 ('continue_chat','Continue an unfinished chat','Return to a previous conversation and continue its current topic.','return_chat',1,100,'{"progress_points":15}'::jsonb),
 ('meet_partner','Chat with someone new','Start a conversation with a partner you have not met.','new_partner',1,80,'{"unlock_progress":true}'::jsonb),
 ('daily_bonus','Claim today’s bonus','Return and claim the available daily check-in.','daily_bonus',1,70,'{"existing_reward_type":"checkin"}'::jsonb),
 ('sponsored_activity','Complete an optional sponsored activity','Open an eligible activity after meaningful engagement and complete verification.','sponsored',1,60,'{"offer_defined":true}'::jsonb)
on conflict(goal_key) do update set title=excluded.title,description=excluded.description,active=true;

insert into public.earn_chat_task_definitions(task_key,title,description,task_type,target,reward_descriptor,minimum_level)
values
 ('chat_goal','Today’s chat goal','Complete today’s primary conversation goal.','chat',1,'{"progress_points":20}'::jsonb,1),
 ('return_conversation','Continue where you stopped','Resume an unfinished conversation.','return',1,'{"progress_points":15}'::jsonb,1),
 ('complete_profile','Complete your profile','Add the details needed to personalise your experience.','profile',1,'{"progress_points":25}'::jsonb,1),
 ('daily_sponsored','Daily sponsored opportunity','Complete an eligible sponsored activity after engagement.','sponsored',1,'{"offer_defined":true}'::jsonb,1),
 ('bonus_challenge','Bonus conversation challenge','Complete the rotating bonus challenge.','bonus',1,'{"unlock_progress":true}'::jsonb,2)
on conflict(task_key) do update set title=excluded.title,description=excluded.description,active=true;

insert into public.earn_chat_user_progression(user_id)
select id from auth.users on conflict(user_id) do nothing;
insert into public.earn_chat_streaks(user_id,current_streak,longest_streak,last_active_date)
select id,greatest(coalesce(current_streak,1),0),greatest(coalesce(longest_streak,1),0),progress_date
from public.profiles on conflict(user_id) do nothing;

alter table public.earn_chat_partners enable row level security;
alter table public.earn_chat_topics enable row level security;
alter table public.earn_chat_threads enable row level security;
alter table public.earn_chat_messages enable row level security;
alter table public.earn_chat_memories enable row level security;
alter table public.earn_chat_level_definitions enable row level security;
alter table public.earn_chat_user_progression enable row level security;
alter table public.earn_chat_streaks enable row level security;
alter table public.earn_chat_goal_templates enable row level security;
alter table public.earn_chat_daily_goals enable row level security;
alter table public.earn_chat_task_definitions enable row level security;
alter table public.earn_chat_daily_tasks enable row level security;
alter table public.earn_chat_sponsored_offers enable row level security;
alter table public.earn_chat_sponsored_opportunities enable row level security;

create policy "active partners readable" on public.earn_chat_partners for select to authenticated using(active);
create policy "active topics readable" on public.earn_chat_topics for select to authenticated using(active);
create policy "active levels readable" on public.earn_chat_level_definitions for select to authenticated using(active);
create policy "active goal templates readable" on public.earn_chat_goal_templates for select to authenticated using(active);
create policy "active task definitions readable" on public.earn_chat_task_definitions for select to authenticated using(active);
create policy "active sponsored offers readable" on public.earn_chat_sponsored_offers for select to authenticated using(active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()));
create policy "users read own threads" on public.earn_chat_threads for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own messages" on public.earn_chat_messages for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own memories" on public.earn_chat_memories for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own progression" on public.earn_chat_user_progression for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own streak" on public.earn_chat_streaks for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own goals" on public.earn_chat_daily_goals for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own tasks" on public.earn_chat_daily_tasks for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own sponsored opportunities" on public.earn_chat_sponsored_opportunities for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());

revoke all on public.earn_chat_partners,public.earn_chat_topics,public.earn_chat_threads,
  public.earn_chat_messages,public.earn_chat_memories,public.earn_chat_level_definitions,
  public.earn_chat_user_progression,public.earn_chat_streaks,public.earn_chat_goal_templates,
  public.earn_chat_daily_goals,public.earn_chat_task_definitions,public.earn_chat_daily_tasks,
  public.earn_chat_sponsored_offers,public.earn_chat_sponsored_opportunities from anon;
revoke insert,update,delete,truncate,trigger,references on
  public.earn_chat_partners,public.earn_chat_topics,public.earn_chat_threads,public.earn_chat_messages,
  public.earn_chat_memories,public.earn_chat_level_definitions,public.earn_chat_user_progression,
  public.earn_chat_streaks,public.earn_chat_goal_templates,public.earn_chat_daily_goals,
  public.earn_chat_task_definitions,public.earn_chat_daily_tasks,public.earn_chat_sponsored_offers,
  public.earn_chat_sponsored_opportunities from authenticated;
grant select on public.earn_chat_partners,public.earn_chat_topics,public.earn_chat_threads,
  public.earn_chat_messages,public.earn_chat_memories,public.earn_chat_level_definitions,
  public.earn_chat_user_progression,public.earn_chat_streaks,public.earn_chat_goal_templates,
  public.earn_chat_daily_goals,public.earn_chat_task_definitions,public.earn_chat_daily_tasks,
  public.earn_chat_sponsored_offers,public.earn_chat_sponsored_opportunities to authenticated;

create or replace function earn_chat_private.bootstrap_daily_platform_user()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  insert into public.earn_chat_user_progression(user_id) values(new.id) on conflict do nothing;
  insert into public.earn_chat_streaks(user_id) values(new.id) on conflict do nothing;
  return new;
end; $$;
revoke all on function earn_chat_private.bootstrap_daily_platform_user() from public,anon,authenticated;
grant execute on function earn_chat_private.bootstrap_daily_platform_user() to service_role;
drop trigger if exists earn_chat_bootstrap_daily_platform on auth.users;
create trigger earn_chat_bootstrap_daily_platform after insert on auth.users
for each row execute function earn_chat_private.bootstrap_daily_platform_user();

commit;
