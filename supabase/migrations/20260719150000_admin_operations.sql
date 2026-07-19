-- Earn Chat Stage 7: paginated admin operations and immutable audit trail.

begin;

create table if not exists public.earn_chat_admin_audit_log (
  id bigint generated always as identity primary key,
  admin_user_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_state jsonb not null default '{}',
  after_state jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index if not exists earn_chat_admin_audit_created_idx on public.earn_chat_admin_audit_log(created_at desc,id desc);
create index if not exists earn_chat_admin_audit_entity_idx on public.earn_chat_admin_audit_log(entity_type,entity_id,created_at desc);
create index if not exists profiles_admin_created_idx on public.profiles(created_at desc,id);
create index if not exists earn_chat_kyc_admin_status_idx on public.earn_chat_kyc_cases(status,updated_at desc);
create index if not exists earn_chat_sharing_admin_status_idx on public.earn_chat_sharing_progress(status,updated_at desc);
create index if not exists earn_chat_threads_admin_status_idx on public.earn_chat_threads(status,updated_at desc);

alter table public.earn_chat_admin_audit_log enable row level security;
create policy "admins read audit log" on public.earn_chat_admin_audit_log for select to authenticated using(public.is_current_user_admin());
revoke all on public.earn_chat_admin_audit_log from anon;
revoke insert,update,delete,truncate,trigger,references on public.earn_chat_admin_audit_log from authenticated;
grant select on public.earn_chat_admin_audit_log to authenticated;

create or replace function earn_chat_private.write_admin_audit(
 p_action text,p_entity_type text,p_entity_id uuid,p_before jsonb,p_after jsonb,p_metadata jsonb default '{}')
returns void language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if auth.uid() is null or not public.is_current_user_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 insert into public.earn_chat_admin_audit_log(admin_user_id,action,entity_type,entity_id,before_state,after_state,metadata)
 values(auth.uid(),p_action,p_entity_type,p_entity_id,coalesce(p_before,'{}'),coalesce(p_after,'{}'),coalesce(p_metadata,'{}'));
end; $$;
revoke all on function earn_chat_private.write_admin_audit(text,text,uuid,jsonb,jsonb,jsonb) from public,anon,authenticated;

create or replace function public.earn_chat_admin_overview()
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null or not public.is_current_user_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 return jsonb_build_object(
  'users',(select count(*) from public.profiles),
  'online_now',(select count(*) from public.site_presence where is_visible and last_seen>now()-interval '5 minutes'),
  'pending_withdrawals',(select count(*) from public.earn_chat_withdrawal_journeys where status in('processing','approved')),
  'pending_kyc',(select count(*) from public.earn_chat_kyc_cases where status='pending'),
  'active_conversations',(select count(*) from public.earn_chat_threads where status in('active','paused')),
  'active_offers',(select count(*) from public.earn_chat_sponsored_offers where active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now())),
  'usd_wallet_total_minor',(select coalesce(sum(amount),0) from public.earning_ledger where currency_code='USD' and status in('credited','adjustment','refunded','held','paid')),
  'errors_24h',(select count(*) from public.analytics_events where created_at>now()-interval '24 hours' and (event_name ilike '%failed%' or event_name ilike '%error%')),
  'generated_at',now()
 );
end; $$;

create or replace function public.earn_chat_admin_page(p_section text,p_page integer default 1,p_page_size integer default 25,p_status text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_page integer:=greatest(coalesce(p_page,1),1); v_size integer:=least(greatest(coalesce(p_page_size,25),1),100); v_offset integer; v_total bigint:=0; v_rows jsonb:='[]';
begin
 if v_uid is null or not public.is_current_user_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 v_offset:=(v_page-1)*v_size;
 if p_section='users' then
  select count(*) into v_total from public.profiles p where p_status is null or (case when p.earning_locked then 'locked' else 'active' end)=p_status;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (
   select p.id,p.full_name,p.email,p.country_code,p.created_at,p.is_admin,p.earning_locked,ps.journey_state,
    coalesce((select sum(l.amount) from public.earning_ledger l where l.user_id=p.id and l.currency_code='USD' and l.status in('credited','adjustment','refunded','held','paid')),0) usd_balance_minor
   from public.profiles p left join public.earn_chat_payout_states ps on ps.user_id=p.id
   where p_status is null or (case when p.earning_locked then 'locked' else 'active' end)=p_status
   order by p.created_at desc nulls last,p.id limit v_size offset v_offset
  ) x;
 elsif p_section='live_users' then
  select count(*) into v_total from public.site_presence where last_seen>now()-interval '30 minutes';
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (
   select session_id,user_id,display_name,display_email,page_id,device,browser,is_visible,last_seen,source,country_code
   from (select s.*,p.country_code from public.site_presence s left join public.profiles p on p.id=s.user_id where s.last_seen>now()-interval '30 minutes') q
   order by last_seen desc limit v_size offset v_offset
  ) x;
 elsif p_section in('offers','reward_slots') then
  select count(*) into v_total from public.earn_chat_sponsored_offers where p_status is null or active=(p_status='active');
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (
   select id,offer_key,title,description,destination_url,placement,minimum_meaningful_replies,minimum_seconds_away,reward_minor,starts_at,ends_at,active,created_at
   from public.earn_chat_sponsored_offers where p_status is null or active=(p_status='active') order by created_at desc limit v_size offset v_offset
  ) x;
 elsif p_section='withdrawals' then
  select count(*) into v_total from public.earn_chat_withdrawal_journeys where p_status is null or status=p_status;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (
   select w.id,w.user_id,p.full_name,p.email,w.amount_minor,w.currency_code,w.country_code,w.payout_method_key,w.payout_details,w.status,w.requested_at,w.processing_at,w.reviewed_at,w.paid_at,w.review_note,w.payment_reference
   from public.earn_chat_withdrawal_journeys w join public.profiles p on p.id=w.user_id
   where p_status is null or w.status=p_status order by w.requested_at desc limit v_size offset v_offset
  ) x;
 elsif p_section='sharing' then
  select count(*) into v_total from public.earn_chat_sharing_progress where p_status is null or status=p_status;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (
   select s.withdrawal_id,s.user_id,p.full_name,p.email,s.status,s.opened_at,s.returned_at,s.completed_at,s.updated_at
   from public.earn_chat_sharing_progress s join public.profiles p on p.id=s.user_id
   where p_status is null or s.status=p_status order by s.updated_at desc limit v_size offset v_offset
  ) x;
 elsif p_section='kyc' then
  select count(*) into v_total from public.earn_chat_kyc_cases where p_status is null or status=p_status;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (
   select k.id,k.user_id,p.full_name profile_name,p.email,k.legal_name,k.date_of_birth,k.country_code,k.document_type,k.document_number_masked,k.status,k.submitted_at,k.reviewed_at,k.review_note,
    (select count(*) from public.earn_chat_kyc_documents d where d.case_id=k.id) document_count
   from public.earn_chat_kyc_cases k join public.profiles p on p.id=k.user_id
   where p_status is null or k.status=p_status order by k.updated_at desc limit v_size offset v_offset
  ) x;
 elsif p_section='conversations' then
  select count(*) into v_total from public.earn_chat_threads where p_status is null or status=p_status;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (
   select t.id,t.user_id,p.email,pa.display_name partner,t.status,t.message_count,t.meaningful_message_count,t.last_message_at,t.completed_at,t.updated_at
   from public.earn_chat_threads t join public.profiles p on p.id=t.user_id join public.earn_chat_partners pa on pa.id=t.partner_id
   where p_status is null or t.status=p_status order by t.updated_at desc limit v_size offset v_offset
  ) x;
 elsif p_section='performance' then
  select count(distinct event_name) into v_total from public.analytics_events where created_at>now()-interval '7 days';
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (
   select event_name,count(*) event_count,count(distinct session_id) sessions,max(created_at) latest
   from public.analytics_events where created_at>now()-interval '7 days' group by event_name order by event_count desc,event_name limit v_size offset v_offset
  ) x;
 elsif p_section='errors' then
  select count(distinct event_name) into v_total from public.analytics_events where created_at>now()-interval '7 days' and (event_name ilike '%failed%' or event_name ilike '%error%');
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (
   select event_name,count(*) event_count,max(created_at) latest from public.analytics_events
   where created_at>now()-interval '7 days' and (event_name ilike '%failed%' or event_name ilike '%error%')
   group by event_name order by event_count desc,event_name limit v_size offset v_offset
  ) x;
 elsif p_section='audit' then
  select count(*) into v_total from public.earn_chat_admin_audit_log where p_status is null or action=p_status;
  select coalesce(jsonb_agg(to_jsonb(x)),'[]') into v_rows from (
   select a.id,a.admin_user_id,p.email admin_email,a.action,a.entity_type,a.entity_id,a.before_state,a.after_state,a.metadata,a.created_at
   from public.earn_chat_admin_audit_log a join public.profiles p on p.id=a.admin_user_id
   where p_status is null or a.action=p_status order by a.created_at desc,a.id desc limit v_size offset v_offset
  ) x;
 elsif p_section='settings' then
  v_total:=2;
  select jsonb_agg(to_jsonb(x)) into v_rows from (
   select 'currency' setting_group,to_jsonb(c) value from public.earn_chat_currency_settings c where id=1
   union all select 'earning',to_jsonb(e) from public.earn_chat_settings e where id=1
  ) x;
 else raise exception 'Unsupported admin section';
 end if;
 return jsonb_build_object('section',p_section,'page',v_page,'page_size',v_size,'total',v_total,'rows',coalesce(v_rows,'[]'::jsonb));
end; $$;

create or replace function public.earn_chat_admin_review_kyc(p_case_id uuid,p_action text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_case public.earn_chat_kyc_cases%rowtype; v_before jsonb; v_status text; v_withdrawal uuid;
begin
 if v_uid is null or not public.is_current_user_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_action not in('approved','rejected','correction_required') then raise exception 'Invalid KYC review action'; end if;
 select * into v_case from public.earn_chat_kyc_cases where id=p_case_id for update;
 if not found or v_case.status not in('pending','correction_required') then raise exception 'KYC case is not reviewable'; end if;
 v_before:=jsonb_build_object('status',v_case.status,'review_note',v_case.review_note);
 v_status:=p_action;
 update public.earn_chat_kyc_cases set status=v_status,review_note=nullif(trim(coalesce(p_note,'')),''),reviewed_at=now(),updated_at=now() where id=v_case.id;
 update public.profiles set kyc_done=(v_status='approved'),kyc_pending=false where id=v_case.user_id;
 select id into v_withdrawal from public.earn_chat_withdrawal_journeys where user_id=v_case.user_id and status in('kyc_pending','correction_required') order by requested_at desc limit 1;
 if v_withdrawal is not null then
  update public.earn_chat_withdrawal_journeys set status=case when v_status='approved' then 'processing' else 'kyc_required' end,processing_at=case when v_status='approved' then now() else processing_at end,review_note=nullif(trim(coalesce(p_note,'')),''),updated_at=now() where id=v_withdrawal;
  update public.earn_chat_payout_states set journey_state=case when v_status='approved' then 'processing' else 'correction_required' end,earnings_paused=(v_status<>'approved'),sponsored_rewards_paused=(v_status<>'approved'),state_changed_at=now(),updated_at=now() where user_id=v_case.user_id;
 end if;
 perform earn_chat_private.write_admin_audit('kyc_'||v_status,'kyc_case',v_case.id,v_before,jsonb_build_object('status',v_status,'review_note',nullif(trim(coalesce(p_note,'')),'')),jsonb_build_object('withdrawal_id',v_withdrawal));
 return jsonb_build_object('case_id',v_case.id,'status',v_status,'withdrawal_id',v_withdrawal);
end; $$;

create or replace function public.earn_chat_admin_review_withdrawal(p_withdrawal_id uuid,p_action text,p_note text default null,p_payment_reference text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_row public.earn_chat_withdrawal_journeys%rowtype; v_before jsonb; v_new text;
begin
 if v_uid is null or not public.is_current_user_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_action not in('approved','paid','rejected','correction_required') then raise exception 'Invalid withdrawal action'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_withdrawal_id::text||':admin',0));
 select * into v_row from public.earn_chat_withdrawal_journeys where id=p_withdrawal_id for update;
 if not found or v_row.status in('paid','rejected','cancelled') then raise exception 'Withdrawal is not reviewable'; end if;
 if p_action='paid' and v_row.status not in('processing','approved') then raise exception 'Withdrawal must be processing or approved before payment'; end if;
 v_before:=jsonb_build_object('status',v_row.status,'review_note',v_row.review_note,'payment_reference',v_row.payment_reference);
 v_new:=p_action;
 if p_action='rejected' then
  insert into public.earning_ledger(user_id,event_key,reward_type,amount,activity_points,cycle_day,earning_date,status,metadata,currency_code,source_type,source_id)
  values(v_row.user_id,'usd:withdrawal_refund:'||v_row.id,'withdrawal_refund',v_row.amount_minor,0,coalesce((select day from public.profiles where id=v_row.user_id),1),(now() at time zone 'Africa/Lagos')::date,'refunded',jsonb_build_object('withdrawal_id',v_row.id),'USD','earn_chat_withdrawal_refund',v_row.id)
  on conflict(user_id,event_key) do nothing;
 end if;
 update public.earn_chat_withdrawal_journeys set status=v_new,review_note=nullif(trim(coalesce(p_note,'')),''),payment_reference=coalesce(nullif(trim(coalesce(p_payment_reference,'')),''),payment_reference),reviewed_at=now(),paid_at=case when p_action='paid' then now() else paid_at end,updated_at=now() where id=v_row.id;
 if p_action='paid' then
  update public.earning_ledger set status='paid',metadata=metadata||jsonb_build_object('paid_at',now(),'payment_reference',nullif(trim(coalesce(p_payment_reference,'')),'')) where id=v_row.hold_ledger_id and status='held';
  update public.profiles set has_withdrawn=true where id=v_row.user_id;
  update public.earn_chat_payout_states set journey_state='earning_resumed',earnings_paused=false,sponsored_rewards_paused=false,cycle_number=cycle_number+1,state_changed_at=now(),updated_at=now() where user_id=v_row.user_id;
 elsif p_action='rejected' then
  update public.earn_chat_payout_states set journey_state='withdrawal_required',earnings_paused=true,sponsored_rewards_paused=true,cycle_number=cycle_number+1,state_changed_at=now(),updated_at=now() where user_id=v_row.user_id;
 elsif p_action='correction_required' then
  update public.earn_chat_payout_states set journey_state='correction_required',earnings_paused=true,sponsored_rewards_paused=true,state_changed_at=now(),updated_at=now() where user_id=v_row.user_id;
 end if;
 perform earn_chat_private.write_admin_audit('withdrawal_'||v_new,'withdrawal',v_row.id,v_before,jsonb_build_object('status',v_new,'review_note',nullif(trim(coalesce(p_note,'')),''),'payment_reference',nullif(trim(coalesce(p_payment_reference,'')),'')),'{}');
 return jsonb_build_object('withdrawal_id',v_row.id,'status',v_new);
end; $$;

create or replace function public.earn_chat_admin_save_offer(p_id uuid,p_offer_key text,p_title text,p_description text,p_destination_url text,p_placement text,p_minimum_replies integer,p_minimum_seconds integer,p_reward_minor bigint,p_active boolean)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_id uuid; v_before jsonb:='{}'; v_after jsonb;
begin
 if v_uid is null or not public.is_current_user_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_offer_key !~ '^[a-z0-9][a-z0-9_-]{2,79}$' or char_length(trim(p_title))<3 or char_length(trim(p_description))<5 then raise exception 'Offer details are invalid'; end if;
 if p_destination_url !~ '^https://[^[:space:]]+$' then raise exception 'Offer destination must use HTTPS'; end if;
 if p_placement not in('inline_chat','daily_task','post_chat') or p_minimum_replies<0 or p_minimum_seconds not between 0 and 3600 or p_reward_minor<0 then raise exception 'Offer rules are invalid'; end if;
 if p_id is not null then select to_jsonb(o) into v_before from public.earn_chat_sponsored_offers o where id=p_id for update;
 if p_id is null then
  insert into public.earn_chat_sponsored_offers(offer_key,title,description,destination_url,placement,minimum_meaningful_replies,minimum_seconds_away,reward_minor,reward_descriptor,active)
  values(p_offer_key,trim(p_title),trim(p_description),p_destination_url,p_placement,p_minimum_replies,p_minimum_seconds,p_reward_minor,jsonb_build_object('currency_code','USD','reward_minor',p_reward_minor),p_active) returning id into v_id;
 else
  update public.earn_chat_sponsored_offers set offer_key=p_offer_key,title=trim(p_title),description=trim(p_description),destination_url=p_destination_url,placement=p_placement,minimum_meaningful_replies=p_minimum_replies,minimum_seconds_away=p_minimum_seconds,reward_minor=p_reward_minor,reward_descriptor=jsonb_build_object('currency_code','USD','reward_minor',p_reward_minor),active=p_active where id=p_id returning id into v_id;
  if v_id is null then raise exception 'Offer not found'; end if;
 end if;
 select to_jsonb(o) into v_after from public.earn_chat_sponsored_offers o where id=v_id;
 perform earn_chat_private.write_admin_audit(case when p_id is null then 'offer_created' else 'offer_updated' end,'sponsored_offer',v_id,v_before,v_after,'{}');
 return v_after;
end; $$;

revoke all on function public.earn_chat_admin_overview() from public,anon;
revoke all on function public.earn_chat_admin_page(text,integer,integer,text) from public,anon;
revoke all on function public.earn_chat_admin_review_kyc(uuid,text,text) from public,anon;
revoke all on function public.earn_chat_admin_review_withdrawal(uuid,text,text,text) from public,anon;
revoke all on function public.earn_chat_admin_save_offer(uuid,text,text,text,text,text,integer,integer,bigint,boolean) from public,anon;
grant execute on function public.earn_chat_admin_overview() to authenticated;
grant execute on function public.earn_chat_admin_page(text,integer,integer,text) to authenticated;
grant execute on function public.earn_chat_admin_review_kyc(uuid,text,text) to authenticated;
grant execute on function public.earn_chat_admin_review_withdrawal(uuid,text,text,text) to authenticated;
grant execute on function public.earn_chat_admin_save_offer(uuid,text,text,text,text,text,integer,integer,bigint,boolean) to authenticated;

commit;
