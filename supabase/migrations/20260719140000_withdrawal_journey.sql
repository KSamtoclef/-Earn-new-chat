-- Earn Chat Stage 6: canonical USD withdrawal, sharing, KYC and processing journey.
-- Legacy NGN withdrawals and KYC records remain read-only compatibility data.

begin;

create table if not exists public.earn_chat_payout_methods (
  id uuid primary key default gen_random_uuid(),
  country_code text not null check(country_code='*' or country_code ~ '^[A-Z]{2}$'),
  method_key text not null,
  display_name text not null,
  required_fields jsonb not null default '[]',
  display_order smallint not null default 1 check(display_order between 1 and 20),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(country_code,method_key)
);

create table if not exists public.earn_chat_payout_states (
  user_id uuid primary key references auth.users(id) on delete cascade,
  journey_state text not null default 'earning_enabled' check(journey_state in(
    'earning_enabled','withdrawal_required','sharing_required','kyc_required','kyc_pending',
    'processing','earning_resumed','correction_required','suspended'
  )),
  earnings_paused boolean not null default false,
  sponsored_rewards_paused boolean not null default false,
  cycle_number integer not null default 1 check(cycle_number>=1),
  state_changed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.earn_chat_withdrawal_journeys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  cycle_number integer not null check(cycle_number>=1),
  amount_minor bigint not null check(amount_minor>0),
  currency_code text not null default 'USD' check(currency_code='USD'),
  country_code text not null check(country_code ~ '^[A-Z]{2}$'),
  payout_method_key text not null,
  payout_details jsonb not null,
  status text not null default 'sharing_required' check(status in(
    'sharing_required','kyc_required','kyc_pending','processing','approved','paid',
    'rejected','correction_required','cancelled'
  )),
  hold_ledger_id uuid references public.earning_ledger(id) on delete restrict,
  requested_at timestamptz not null default now(),
  processing_at timestamptz,
  reviewed_at timestamptz,
  paid_at timestamptz,
  review_note text,
  payment_reference text,
  updated_at timestamptz not null default now(),
  unique(user_id,cycle_number)
);
create unique index if not exists earn_chat_one_open_withdrawal_idx
  on public.earn_chat_withdrawal_journeys(user_id)
  where status in('sharing_required','kyc_required','kyc_pending','processing','approved','correction_required');
create index if not exists earn_chat_withdrawal_admin_idx
  on public.earn_chat_withdrawal_journeys(status,requested_at desc);

create table if not exists public.earn_chat_sharing_progress (
  withdrawal_id uuid primary key references public.earn_chat_withdrawal_journeys(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  share_token uuid not null default gen_random_uuid() unique,
  opened_at timestamptz,
  returned_at timestamptz,
  completed_at timestamptz,
  status text not null default 'required' check(status in('required','opened','completed')),
  updated_at timestamptz not null default now()
);

create table if not exists public.earn_chat_kyc_cases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  legal_name text,
  date_of_birth date,
  country_code text check(country_code is null or country_code ~ '^[A-Z]{2}$'),
  document_type text check(document_type is null or document_type in('national_id','passport','drivers_licence','voter_card')),
  document_number_masked text,
  status text not null default 'not_submitted' check(status in('not_submitted','pending','approved','rejected','correction_required')),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.earn_chat_kyc_documents (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.earn_chat_kyc_cases(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  document_side text not null check(document_side in('front','back','selfie')),
  storage_path text not null unique,
  mime_type text not null check(mime_type in('image/jpeg','image/png','image/webp','application/pdf')),
  file_size bigint not null check(file_size between 1 and 10485760),
  created_at timestamptz not null default now(),
  unique(case_id,document_side)
);

insert into public.earn_chat_payout_methods(country_code,method_key,display_name,required_fields,display_order)
values
 ('NG','bank_transfer','Nigerian bank transfer','["account_name","account_number","bank_name"]',1),
 ('GH','mobile_money','Ghana mobile money','["account_name","mobile_number","network"]',1),
 ('GH','bank_transfer','Ghana bank transfer','["account_name","account_number","bank_name"]',2),
 ('CM','mobile_money','Cameroon mobile money','["account_name","mobile_number","network"]',1),
 ('MZ','mobile_money','Mozambique mobile money','["account_name","mobile_number","network"]',1),
 ('KE','mobile_money','Kenya mobile money','["account_name","mobile_number","network"]',1),
 ('ZA','bank_transfer','South African bank transfer','["account_name","account_number","bank_name","branch_code"]',1),
 ('*','international_bank','International bank transfer','["account_name","account_number_or_iban","bank_name","swift_code"]',10)
on conflict(country_code,method_key) do update set
 display_name=excluded.display_name,required_fields=excluded.required_fields,
 display_order=excluded.display_order,active=true;

insert into public.earn_chat_payout_states(user_id,journey_state,earnings_paused,sponsored_rewards_paused)
select u.id,
 case when coalesce((select sum(l.amount) from public.earning_ledger l where l.user_id=u.id and l.currency_code='USD' and l.status in('credited','adjustment','refunded','held','paid')),0)>=s.minimum_withdrawal_minor
      and not coalesce(p.has_withdrawn,false) then 'withdrawal_required' else 'earning_enabled' end,
 case when coalesce((select sum(l.amount) from public.earning_ledger l where l.user_id=u.id and l.currency_code='USD' and l.status in('credited','adjustment','refunded','held','paid')),0)>=s.minimum_withdrawal_minor
      and not coalesce(p.has_withdrawn,false) then true else false end,
 case when coalesce((select sum(l.amount) from public.earning_ledger l where l.user_id=u.id and l.currency_code='USD' and l.status in('credited','adjustment','refunded','held','paid')),0)>=s.minimum_withdrawal_minor
      and not coalesce(p.has_withdrawn,false) then true else false end
from auth.users u join public.profiles p on p.id=u.id cross join public.earn_chat_currency_settings s
where s.id=1
on conflict(user_id) do nothing;

create or replace function earn_chat_private.bootstrap_payout_state()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 insert into public.earn_chat_payout_states(user_id)
 values(new.id) on conflict(user_id) do nothing;
 return new;
end; $$;
revoke all on function earn_chat_private.bootstrap_payout_state() from public,anon,authenticated;
drop trigger if exists earn_chat_bootstrap_payout_state on public.profiles;
create trigger earn_chat_bootstrap_payout_state after insert on public.profiles
for each row execute function earn_chat_private.bootstrap_payout_state();

insert into public.earn_chat_kyc_cases(user_id,status,submitted_at,reviewed_at,created_at,updated_at)
select k.user_id,
 case k.status when 'approved' then 'approved' when 'rejected' then 'rejected' else 'pending' end,
 k.submitted_at,k.reviewed_at,coalesce(k.submitted_at,now()),coalesce(k.updated_at,now())
from public.kyc_submissions k
on conflict(user_id) do nothing;

create or replace function earn_chat_private.block_paused_usd_rewards()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if new.currency_code='USD' and new.amount>0 and new.status='credited'
    and new.reward_type in('meaningful_reply','sponsored_activity')
    and exists(select 1 from public.earn_chat_payout_states where user_id=new.user_id and (earnings_paused or sponsored_rewards_paused)) then
   return null;
 end if;
 return new;
end; $$;
revoke all on function earn_chat_private.block_paused_usd_rewards() from public,anon,authenticated;
drop trigger if exists earn_chat_block_paused_usd_rewards on public.earning_ledger;
create trigger earn_chat_block_paused_usd_rewards before insert on public.earning_ledger
for each row execute function earn_chat_private.block_paused_usd_rewards();

create or replace function earn_chat_private.sync_usd_withdrawal_threshold()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_balance bigint; v_minimum bigint; v_withdrawn boolean;
begin
 if new.currency_code<>'USD' then return new; end if;
 select coalesce(sum(amount),0) into v_balance from public.earning_ledger
 where user_id=new.user_id and currency_code='USD' and status in('credited','adjustment','refunded','held','paid');
 select s.minimum_withdrawal_minor,coalesce(p.has_withdrawn,false) into v_minimum,v_withdrawn
 from public.earn_chat_currency_settings s cross join public.profiles p where s.id=1 and p.id=new.user_id;
 if not v_withdrawn and v_balance>=v_minimum then
   insert into public.earn_chat_payout_states(user_id,journey_state,earnings_paused,sponsored_rewards_paused,state_changed_at,updated_at)
   values(new.user_id,'withdrawal_required',true,true,now(),now())
   on conflict(user_id) do update set journey_state=case when earn_chat_payout_states.journey_state='earning_enabled' then 'withdrawal_required' else earn_chat_payout_states.journey_state end,
    earnings_paused=case when earn_chat_payout_states.journey_state='earning_enabled' then true else earn_chat_payout_states.earnings_paused end,
    sponsored_rewards_paused=case when earn_chat_payout_states.journey_state='earning_enabled' then true else earn_chat_payout_states.sponsored_rewards_paused end,
    state_changed_at=case when earn_chat_payout_states.journey_state='earning_enabled' then now() else earn_chat_payout_states.state_changed_at end,updated_at=now();
 end if;
 return new;
end; $$;
revoke all on function earn_chat_private.sync_usd_withdrawal_threshold() from public,anon,authenticated;
drop trigger if exists earn_chat_sync_withdrawal_threshold on public.earning_ledger;
create trigger earn_chat_sync_withdrawal_threshold after insert on public.earning_ledger
for each row execute function earn_chat_private.sync_usd_withdrawal_threshold();

alter function public.earn_chat_get_inline_sponsored(uuid)
  rename to earn_chat_get_inline_sponsored_unpaused;
revoke all on function public.earn_chat_get_inline_sponsored_unpaused(uuid) from public,anon,authenticated;

create function public.earn_chat_get_inline_sponsored(p_thread_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if exists(select 1 from public.earn_chat_payout_states where user_id=v_uid and sponsored_rewards_paused) then return null; end if;
 return public.earn_chat_get_inline_sponsored_unpaused(p_thread_id);
end; $$;

create or replace function public.earn_chat_get_payout_state()
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_balance bigint; v_state public.earn_chat_payout_states%rowtype; v_country text; v_withdrawal public.earn_chat_withdrawal_journeys%rowtype;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select * into v_state from public.earn_chat_payout_states where user_id=v_uid;
 select country_code into v_country from public.profiles where id=v_uid;
 select coalesce(sum(amount),0) into v_balance from public.earning_ledger where user_id=v_uid and currency_code='USD' and status in('credited','adjustment','refunded','held','paid');
 select * into v_withdrawal from public.earn_chat_withdrawal_journeys where user_id=v_uid order by requested_at desc limit 1;
 return jsonb_build_object(
  'journey_state',v_state.journey_state,'earnings_paused',v_state.earnings_paused,'sponsored_rewards_paused',v_state.sponsored_rewards_paused,
  'cycle_number',v_state.cycle_number,'available_balance_minor',v_balance,'currency_code','USD','country_code',v_country,
  'settings',(select jsonb_build_object('minimum_minor',minimum_withdrawal_minor,'first_cycle_maximum_minor',first_cycle_maximum_minor) from public.earn_chat_currency_settings where id=1),
  'payout_methods',coalesce((select jsonb_agg(jsonb_build_object('method_key',method_key,'display_name',display_name,'required_fields',required_fields) order by display_order) from public.earn_chat_payout_methods where active and country_code in(v_country,'*')),'[]'::jsonb),
  'withdrawal',case when v_withdrawal.id is null then null else jsonb_build_object('id',v_withdrawal.id,'amount_minor',v_withdrawal.amount_minor,'status',v_withdrawal.status,'requested_at',v_withdrawal.requested_at,'review_note',v_withdrawal.review_note) end,
  'sharing',(select to_jsonb(s)-'share_token'-'user_id' from public.earn_chat_sharing_progress s where s.withdrawal_id=v_withdrawal.id),
  'kyc',(select jsonb_build_object('status',k.status,'submitted_at',k.submitted_at,'review_note',k.review_note) from public.earn_chat_kyc_cases k where k.user_id=v_uid)
 );
end; $$;

create or replace function public.earn_chat_request_usd_withdrawal(p_amount_minor bigint,p_method_key text,p_payout_details jsonb,p_date_of_birth date)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_state public.earn_chat_payout_states%rowtype; v_balance bigint; v_max bigint; v_min bigint; v_country text; v_required jsonb; v_field text; v_id uuid; v_hold uuid;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_uid::text||':withdrawal',0));
 if p_date_of_birth is null or p_date_of_birth>current_date-interval '18 years' then raise exception 'Payouts require an account holder aged 18 or older'; end if;
 select * into v_state from public.earn_chat_payout_states where user_id=v_uid for update;
 if v_state.journey_state<>'withdrawal_required' then raise exception 'Withdrawal is not currently available'; end if;
 select p.country_code,s.minimum_withdrawal_minor,s.first_cycle_maximum_minor into v_country,v_min,v_max
 from public.profiles p cross join public.earn_chat_currency_settings s where p.id=v_uid and s.id=1;
 if v_country is null then raise exception 'Select your country before withdrawal'; end if;
 select required_fields into v_required from public.earn_chat_payout_methods
 where active and method_key=p_method_key and country_code in(v_country,'*') order by case when country_code=v_country then 0 else 1 end limit 1;
 if v_required is null then raise exception 'Payout method is unavailable for this country'; end if;
 for v_field in select jsonb_array_elements_text(v_required) loop
   if nullif(trim(coalesce(p_payout_details->>v_field,'')),'') is null then raise exception 'Missing payout field: %',v_field; end if;
 end loop;
 select coalesce(sum(amount),0) into v_balance from public.earning_ledger where user_id=v_uid and currency_code='USD' and status in('credited','adjustment','refunded','held','paid');
 if p_amount_minor<v_min or p_amount_minor>least(v_balance,v_max) then raise exception 'Withdrawal amount is outside the allowed range'; end if;
 insert into public.earn_chat_withdrawal_journeys(user_id,cycle_number,amount_minor,country_code,payout_method_key,payout_details,status)
 values(v_uid,v_state.cycle_number,p_amount_minor,v_country,p_method_key,p_payout_details,'sharing_required') returning id into v_id;
 insert into public.earning_ledger(user_id,event_key,reward_type,amount,activity_points,cycle_day,earning_date,status,metadata,currency_code,source_type,source_id)
 values(v_uid,'usd:withdrawal_hold:'||v_id,'withdrawal_hold',-p_amount_minor,0,coalesce((select day from public.profiles where id=v_uid),1),(now() at time zone 'Africa/Lagos')::date,'held',jsonb_build_object('withdrawal_id',v_id),'USD','earn_chat_withdrawal',v_id)
 returning id into v_hold;
 update public.earn_chat_withdrawal_journeys set hold_ledger_id=v_hold where id=v_id;
 insert into public.earn_chat_sharing_progress(withdrawal_id,user_id) values(v_id,v_uid);
 insert into public.earn_chat_kyc_cases(user_id,date_of_birth,country_code) values(v_uid,p_date_of_birth,v_country)
 on conflict(user_id) do update set date_of_birth=coalesce(earn_chat_kyc_cases.date_of_birth,excluded.date_of_birth),country_code=coalesce(earn_chat_kyc_cases.country_code,excluded.country_code),updated_at=now();
 update public.earn_chat_payout_states set journey_state='sharing_required',earnings_paused=true,sponsored_rewards_paused=true,state_changed_at=now(),updated_at=now() where user_id=v_uid;
 return jsonb_build_object('withdrawal_id',v_id,'status','sharing_required','amount_minor',p_amount_minor,'currency_code','USD');
end; $$;

create or replace function public.earn_chat_begin_required_share(p_withdrawal_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_row public.earn_chat_sharing_progress%rowtype;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 update public.earn_chat_sharing_progress set status=case when status='required' then 'opened' else status end,opened_at=coalesce(opened_at,now()),updated_at=now()
 where withdrawal_id=p_withdrawal_id and user_id=v_uid and status in('required','opened') returning * into v_row;
 if not found then raise exception 'Sharing step is unavailable'; end if;
 return jsonb_build_object('withdrawal_id',p_withdrawal_id,'status',v_row.status,'share_token',v_row.share_token);
end; $$;

create or replace function public.earn_chat_complete_required_share(p_withdrawal_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_row public.earn_chat_sharing_progress%rowtype; v_kyc text; v_next text;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select * into v_row from public.earn_chat_sharing_progress where withdrawal_id=p_withdrawal_id and user_id=v_uid for update;
 if not found or v_row.status<>'opened' or v_row.opened_at>now()-interval '5 seconds' then raise exception 'Complete the sharing step before continuing'; end if;
 update public.earn_chat_sharing_progress set status='completed',returned_at=now(),completed_at=now(),updated_at=now() where withdrawal_id=p_withdrawal_id;
 select status into v_kyc from public.earn_chat_kyc_cases where user_id=v_uid;
 v_next:=case when v_kyc='approved' then 'processing' else 'kyc_required' end;
 update public.earn_chat_withdrawal_journeys set status=v_next,processing_at=case when v_next='processing' then now() else null end,updated_at=now() where id=p_withdrawal_id and user_id=v_uid;
 update public.earn_chat_payout_states set journey_state=v_next,earnings_paused=case when v_next='processing' then false else true end,sponsored_rewards_paused=case when v_next='processing' then false else true end,state_changed_at=now(),updated_at=now() where user_id=v_uid;
 return jsonb_build_object('withdrawal_id',p_withdrawal_id,'status',v_next);
end; $$;

create or replace function public.earn_chat_submit_kyc(p_legal_name text,p_date_of_birth date,p_document_type text,p_document_number text,p_documents jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_case uuid; v_withdrawal uuid; v_doc jsonb;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if char_length(trim(coalesce(p_legal_name,'')))<3 then raise exception 'Legal name is required'; end if;
 if p_date_of_birth is null or p_date_of_birth>current_date-interval '18 years' then raise exception 'KYC requires an account holder aged 18 or older'; end if;
 if p_document_type not in('national_id','passport','drivers_licence','voter_card') then raise exception 'Unsupported identity document'; end if;
 if char_length(trim(coalesce(p_document_number,'')))<4 then raise exception 'Document number is required'; end if;
 select id into v_withdrawal from public.earn_chat_withdrawal_journeys where user_id=v_uid and status='kyc_required' order by requested_at desc limit 1;
 if v_withdrawal is null then raise exception 'KYC step is unavailable'; end if;
 insert into public.earn_chat_kyc_cases(user_id,legal_name,date_of_birth,country_code,document_type,document_number_masked,status,submitted_at,updated_at)
 values(v_uid,trim(p_legal_name),p_date_of_birth,(select country_code from public.profiles where id=v_uid),p_document_type,'***'||right(trim(p_document_number),4),'pending',now(),now())
 on conflict(user_id) do update set legal_name=excluded.legal_name,date_of_birth=excluded.date_of_birth,country_code=excluded.country_code,document_type=excluded.document_type,document_number_masked=excluded.document_number_masked,status='pending',submitted_at=now(),review_note=null,updated_at=now()
 returning id into v_case;
 delete from public.earn_chat_kyc_documents where case_id=v_case;
 for v_doc in select value from jsonb_array_elements(coalesce(p_documents,'[]'::jsonb)) loop
   if v_doc->>'storage_path' not like v_uid::text||'/%' then raise exception 'Invalid KYC document path'; end if;
   insert into public.earn_chat_kyc_documents(case_id,user_id,document_side,storage_path,mime_type,file_size)
   values(v_case,v_uid,v_doc->>'document_side',v_doc->>'storage_path',v_doc->>'mime_type',(v_doc->>'file_size')::bigint);
 end loop;
 if not exists(select 1 from public.earn_chat_kyc_documents where case_id=v_case and document_side='front') then raise exception 'Front identity document is required'; end if;
 update public.earn_chat_withdrawal_journeys set status='kyc_pending',updated_at=now() where id=v_withdrawal;
 update public.earn_chat_payout_states set journey_state='kyc_pending',earnings_paused=true,sponsored_rewards_paused=true,state_changed_at=now(),updated_at=now() where user_id=v_uid;
 return jsonb_build_object('case_id',v_case,'status','kyc_pending');
end; $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('earn-chat-kyc','earn-chat-kyc',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

alter table public.earn_chat_payout_methods enable row level security;
alter table public.earn_chat_payout_states enable row level security;
alter table public.earn_chat_withdrawal_journeys enable row level security;
alter table public.earn_chat_sharing_progress enable row level security;
alter table public.earn_chat_kyc_cases enable row level security;
alter table public.earn_chat_kyc_documents enable row level security;

create policy "active payout methods readable" on public.earn_chat_payout_methods for select to authenticated using(active);
create policy "users read own payout state" on public.earn_chat_payout_states for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own USD withdrawals" on public.earn_chat_withdrawal_journeys for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own sharing progress" on public.earn_chat_sharing_progress for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own KYC case" on public.earn_chat_kyc_cases for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());
create policy "users read own KYC metadata" on public.earn_chat_kyc_documents for select to authenticated using(user_id=auth.uid() or public.is_current_user_admin());

create policy "users upload own KYC objects" on storage.objects for insert to authenticated
with check(bucket_id='earn-chat-kyc' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "users read own KYC objects" on storage.objects for select to authenticated
using(bucket_id='earn-chat-kyc' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_current_user_admin()));

revoke all on public.earn_chat_payout_methods,public.earn_chat_payout_states,public.earn_chat_withdrawal_journeys,public.earn_chat_sharing_progress,public.earn_chat_kyc_cases,public.earn_chat_kyc_documents from anon;
revoke insert,update,delete,truncate,trigger,references on public.earn_chat_payout_methods,public.earn_chat_payout_states,public.earn_chat_withdrawal_journeys,public.earn_chat_sharing_progress,public.earn_chat_kyc_cases,public.earn_chat_kyc_documents from authenticated;
grant select on public.earn_chat_payout_methods,public.earn_chat_payout_states,public.earn_chat_withdrawal_journeys,public.earn_chat_sharing_progress,public.earn_chat_kyc_cases,public.earn_chat_kyc_documents to authenticated;

revoke all on function public.earn_chat_get_payout_state() from public,anon;
revoke all on function public.earn_chat_get_inline_sponsored(uuid) from public,anon;
revoke all on function public.earn_chat_request_usd_withdrawal(bigint,text,jsonb,date) from public,anon;
revoke all on function public.earn_chat_begin_required_share(uuid) from public,anon;
revoke all on function public.earn_chat_complete_required_share(uuid) from public,anon;
revoke all on function public.earn_chat_submit_kyc(text,date,text,text,jsonb) from public,anon;
grant execute on function public.earn_chat_get_payout_state() to authenticated;
grant execute on function public.earn_chat_get_inline_sponsored(uuid) to authenticated;
grant execute on function public.earn_chat_request_usd_withdrawal(bigint,text,jsonb,date) to authenticated;
grant execute on function public.earn_chat_begin_required_share(uuid) to authenticated;
grant execute on function public.earn_chat_complete_required_share(uuid) to authenticated;
grant execute on function public.earn_chat_submit_kyc(text,date,text,text,jsonb) to authenticated;

commit;
