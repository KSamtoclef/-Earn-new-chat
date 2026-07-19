-- Earn Chat Stage 5: USD wallet configuration and meaningful-chat rewards.
-- Existing ledger rows and profile balances remain NGN compatibility data.

begin;

alter table public.earning_ledger add column if not exists currency_code text;
update public.earning_ledger set currency_code='NGN' where currency_code is null;
alter table public.earning_ledger alter column currency_code set default 'NGN';
alter table public.earning_ledger alter column currency_code set not null;
alter table public.earning_ledger drop constraint if exists earning_ledger_currency_code_check;
alter table public.earning_ledger add constraint earning_ledger_currency_code_check check(currency_code in('NGN','USD'));
alter table public.earning_ledger add column if not exists source_type text;
alter table public.earning_ledger add column if not exists source_id uuid;
create unique index if not exists earning_ledger_currency_source_key
  on public.earning_ledger(user_id,currency_code,source_type,source_id)
  where source_type is not null and source_id is not null;
create index if not exists earning_ledger_wallet_idx
  on public.earning_ledger(user_id,currency_code,earning_date,created_at desc);

alter table public.profiles add column if not exists country_code text;
alter table public.profiles add column if not exists preferred_currency text not null default 'USD';
alter table public.profiles drop constraint if exists profiles_country_code_check;
alter table public.profiles add constraint profiles_country_code_check check(country_code is null or country_code ~ '^[A-Z]{2}$');
alter table public.profiles drop constraint if exists profiles_preferred_currency_check;
alter table public.profiles add constraint profiles_preferred_currency_check check(preferred_currency in('USD','NGN','GHS','XAF','MZN','KES','ZAR','UGX','TZS','RWF','GBP','EUR','CAD','AUD'));
update public.profiles p set country_code=upper(u.raw_user_meta_data->>'country_code')
from auth.users u where u.id=p.id and p.country_code is null and u.raw_user_meta_data->>'country_code' ~ '^[A-Za-z]{2}$';

create table if not exists public.earn_chat_currency_settings (
  id smallint primary key default 1 check(id=1),
  earning_currency text not null default 'USD' check(earning_currency='USD'),
  signup_bonus_minor bigint not null check(signup_bonus_minor>=0),
  meaningful_reply_minor bigint not null check(meaningful_reply_minor>=0),
  standard_daily_cap_minor bigint not null check(standard_daily_cap_minor>0),
  returning_daily_cap_minor bigint not null check(returning_daily_cap_minor>=standard_daily_cap_minor),
  minimum_withdrawal_minor bigint not null check(minimum_withdrawal_minor>0),
  first_cycle_maximum_minor bigint not null check(first_cycle_maximum_minor>=minimum_withdrawal_minor),
  updated_at timestamptz not null default now()
);
insert into public.earn_chat_currency_settings
 (id,earning_currency,signup_bonus_minor,meaningful_reply_minor,standard_daily_cap_minor,returning_daily_cap_minor,minimum_withdrawal_minor,first_cycle_maximum_minor)
values(1,'USD',500,200,3000,4000,15000,30000)
on conflict(id) do update set earning_currency=excluded.earning_currency,signup_bonus_minor=excluded.signup_bonus_minor,
 meaningful_reply_minor=excluded.meaningful_reply_minor,standard_daily_cap_minor=excluded.standard_daily_cap_minor,
 returning_daily_cap_minor=excluded.returning_daily_cap_minor,minimum_withdrawal_minor=excluded.minimum_withdrawal_minor,
 first_cycle_maximum_minor=excluded.first_cycle_maximum_minor,updated_at=now();
alter table public.earn_chat_currency_settings enable row level security;
drop policy if exists "currency settings readable" on public.earn_chat_currency_settings;
create policy "currency settings readable" on public.earn_chat_currency_settings for select to authenticated using(id=1);
revoke all on public.earn_chat_currency_settings from anon;
revoke insert,update,delete,truncate,trigger,references on public.earn_chat_currency_settings from authenticated;
grant select on public.earn_chat_currency_settings to authenticated;

create or replace function earn_chat_private.append_usd_entry(
 p_user_id uuid,p_event_key text,p_reward_type text,p_amount_minor bigint,p_source_type text,p_source_id uuid,p_metadata jsonb default '{}')
returns bigint language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_date date:=(now() at time zone 'Africa/Lagos')::date; v_cap bigint; v_today bigint; v_credit bigint;
begin
 if p_user_id is null or p_amount_minor<0 then raise exception 'Invalid wallet entry'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,0));
 if exists(select 1 from public.earning_ledger where user_id=p_user_id and event_key=p_event_key) then
   return 0;
 end if;
 select case when coalesce(p.has_withdrawn,false) then s.returning_daily_cap_minor else s.standard_daily_cap_minor end
 into v_cap from public.profiles p cross join public.earn_chat_currency_settings s where p.id=p_user_id and s.id=1;
 select coalesce(sum(amount),0) into v_today from public.earning_ledger
 where user_id=p_user_id and currency_code='USD' and earning_date=v_date and status in('credited','adjustment','refunded');
 v_credit:=least(p_amount_minor,greatest(v_cap-v_today,0));
 if v_credit<=0 then return 0; end if;
 insert into public.earning_ledger(user_id,event_key,reward_type,amount,activity_points,cycle_day,earning_date,status,metadata,currency_code,source_type,source_id)
 values(p_user_id,p_event_key,p_reward_type,v_credit,0,coalesce((select day from public.profiles where id=p_user_id),1),v_date,'credited',coalesce(p_metadata,'{}'), 'USD',p_source_type,p_source_id)
 on conflict(user_id,event_key) do nothing;
 return case when found then v_credit else 0 end;
end; $$;
revoke all on function earn_chat_private.append_usd_entry(uuid,text,text,bigint,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function earn_chat_private.append_usd_entry(uuid,text,text,bigint,text,uuid,jsonb) to service_role;

create or replace function earn_chat_private.credit_meaningful_chat_message()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_amount bigint;
begin
 if new.sender='user' and new.quality_label='meaningful' then
   select meaningful_reply_minor into v_amount from public.earn_chat_currency_settings where id=1;
   perform earn_chat_private.append_usd_entry(new.user_id,'usd:meaningful_reply:'||new.id,'meaningful_reply',v_amount,'earn_chat_message',new.id,
    jsonb_build_object('thread_id',new.thread_id,'quality_score',new.quality_score));
 end if;
 return new;
end; $$;
revoke all on function earn_chat_private.credit_meaningful_chat_message() from public,anon,authenticated;
grant execute on function earn_chat_private.credit_meaningful_chat_message() to service_role;
drop trigger if exists earn_chat_credit_meaningful_message on public.earn_chat_messages;
create trigger earn_chat_credit_meaningful_message after insert on public.earn_chat_messages
for each row execute function earn_chat_private.credit_meaningful_chat_message();

create or replace function earn_chat_private.bootstrap_auth_user()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_legacy_bonus bigint; v_usd_bonus bigint; v_name text; v_country text;
begin
 select signup_bonus into v_legacy_bonus from public.earn_chat_settings where id=1;
 select signup_bonus_minor into v_usd_bonus from public.earn_chat_currency_settings where id=1;
 v_legacy_bonus:=coalesce(v_legacy_bonus,2000);
 v_usd_bonus:=coalesce(v_usd_bonus,500);
 v_name:=nullif(trim(coalesce(new.raw_user_meta_data->>'full_name',new.raw_user_meta_data->>'name','')),'');
 v_country:=case when new.raw_user_meta_data->>'country_code' ~ '^[A-Za-z]{2}$' then upper(new.raw_user_meta_data->>'country_code') end;
 insert into public.profiles(id,full_name,email,balance,today_earnings,country_code,preferred_currency)
 values(new.id,v_name,new.email,v_legacy_bonus,v_legacy_bonus,v_country,'USD') on conflict(id) do nothing;
 insert into public.earning_ledger(user_id,event_key,reward_type,amount,activity_points,cycle_day,earning_date,status,metadata,currency_code)
 values(new.id,'signup_bonus','signup_bonus',v_legacy_bonus,0,1,(now() at time zone 'Africa/Lagos')::date,'credited',jsonb_build_object('source','legacy_auth_bootstrap'),'NGN')
 on conflict(user_id,event_key) do nothing;
 insert into public.earning_ledger(user_id,event_key,reward_type,amount,activity_points,cycle_day,earning_date,status,metadata,currency_code)
 values(new.id,'usd:signup_bonus','signup_bonus',v_usd_bonus,0,1,(now() at time zone 'Africa/Lagos')::date,'credited',jsonb_build_object('source','international_auth_bootstrap'),'USD')
 on conflict(user_id,event_key) do nothing;
 return new;
end; $$;
revoke all on function earn_chat_private.bootstrap_auth_user() from public,anon,authenticated;
grant execute on function earn_chat_private.bootstrap_auth_user() to service_role;

create or replace function public.earn_chat_get_wallet_state()
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_date date:=(now() at time zone 'Africa/Lagos')::date; v_result jsonb;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select jsonb_build_object(
  'earning_currency','USD','country_code',p.country_code,'preferred_currency',p.preferred_currency,
  'balances',jsonb_build_object(
    'USD',coalesce((select sum(amount) from public.earning_ledger where user_id=v_uid and currency_code='USD' and status in('credited','adjustment','refunded')),0),
    'NGN',coalesce(p.balance,0)),
  'today_usd_minor',coalesce((select sum(amount) from public.earning_ledger where user_id=v_uid and currency_code='USD' and earning_date=v_date and status in('credited','adjustment','refunded')),0),
  'settings',to_jsonb(s)
 ) into v_result from public.profiles p cross join public.earn_chat_currency_settings s where p.id=v_uid and s.id=1;
 return v_result;
end; $$;

create or replace function public.earn_chat_set_country(p_country_code text,p_preferred_currency text default 'USD')
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_country text:=upper(trim(p_country_code)); v_currency text:=upper(trim(p_preferred_currency));
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 if v_country !~ '^[A-Z]{2}$' then raise exception 'Invalid country'; end if;
 if v_currency not in('USD','NGN','GHS','XAF','MZN','KES','ZAR','UGX','TZS','RWF','GBP','EUR','CAD','AUD') then raise exception 'Unsupported display currency'; end if;
 update public.profiles set country_code=v_country,preferred_currency=v_currency where id=v_uid;
 return jsonb_build_object('country_code',v_country,'preferred_currency',v_currency);
end; $$;

revoke all on function public.earn_chat_get_wallet_state() from public,anon;
revoke all on function public.earn_chat_set_country(text,text) from public,anon;
grant execute on function public.earn_chat_get_wallet_state() to authenticated;
grant execute on function public.earn_chat_set_country(text,text) to authenticated;

commit;
