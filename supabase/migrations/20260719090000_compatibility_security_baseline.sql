-- Earn Chat Stage 3A: compatibility and security baseline
-- Preserves existing balances and history while closing legacy client-write paths.

begin;

create schema if not exists earn_chat_private;
revoke all on schema earn_chat_private from public, anon, authenticated;
grant usage on schema earn_chat_private to service_role;

create or replace function earn_chat_private.bootstrap_auth_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_bonus bigint;
  v_name text;
begin
  select signup_bonus into v_bonus from public.earn_chat_settings where id = 1;
  v_bonus := coalesce(v_bonus, 2000);
  v_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', '')), '');

  insert into public.profiles (id, full_name, email, balance, today_earnings)
  values (new.id, v_name, new.email, v_bonus, v_bonus)
  on conflict (id) do nothing;

  insert into public.earning_ledger
    (user_id, event_key, reward_type, amount, activity_points, cycle_day, earning_date, status, metadata)
  values
    (new.id, 'signup_bonus', 'signup_bonus', v_bonus, 0, 1,
     (now() at time zone 'Africa/Lagos')::date, 'credited',
     jsonb_build_object('source', 'auth_bootstrap'))
  on conflict (user_id, event_key) do nothing;

  return new;
end;
$$;

revoke all on function earn_chat_private.bootstrap_auth_user() from public, anon, authenticated;
grant execute on function earn_chat_private.bootstrap_auth_user() to service_role;

drop trigger if exists earn_chat_bootstrap_user on auth.users;
create trigger earn_chat_bootstrap_user
after insert on auth.users
for each row execute function earn_chat_private.bootstrap_auth_user();

with inserted as (
  insert into public.profiles (id, full_name, email, balance, today_earnings)
  select
    u.id,
    nullif(trim(coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name', '')), ''),
    u.email,
    s.signup_bonus,
    s.signup_bonus
  from auth.users u
  cross join public.earn_chat_settings s
  left join public.profiles p on p.id = u.id
  where s.id = 1 and p.id is null
  on conflict (id) do nothing
  returning id
)
insert into public.earning_ledger
  (user_id, event_key, reward_type, amount, activity_points, cycle_day, earning_date, status, metadata)
select i.id, 'signup_bonus', 'signup_bonus', s.signup_bonus, 0, 1,
       (now() at time zone 'Africa/Lagos')::date, 'credited',
       jsonb_build_object('source', 'stage_3a_profile_backfill')
from inserted i cross join public.earn_chat_settings s
where s.id = 1
on conflict (user_id, event_key) do nothing;

update public.profiles p
set kyc_done = (k.status = 'approved'),
    kyc_pending = (k.status = 'pending')
from public.kyc_submissions k
where k.user_id = p.id
  and (p.kyc_done is distinct from (k.status = 'approved')
    or p.kyc_pending is distinct from (k.status = 'pending'));

update public.profiles p
set kyc_done = false, kyc_pending = false
where not exists (select 1 from public.kyc_submissions k where k.user_id = p.id)
  and (coalesce(p.kyc_done, false) or coalesce(p.kyc_pending, false));

drop policy if exists "Admin read all" on public.profiles;
drop policy if exists "Allow insert" on public.profiles;
drop policy if exists "Allow select" on public.profiles;
drop policy if exists "Allow update" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "Users can view own profile" on public.profiles;
drop policy if exists "users read own secure profile" on public.profiles;
create policy "users read own secure profile" on public.profiles
for select to authenticated
using (id = auth.uid() or public.is_current_user_admin());

drop policy if exists "Open insert" on public.cte_registrations;
drop policy if exists "Open select" on public.cte_registrations;

revoke all on public.profiles from public, anon, authenticated;
revoke all on public.cte_registrations from public, anon, authenticated;
revoke all on public.earn_chat_settings from public, anon, authenticated;
revoke all on public.chat_reward_sessions from public, anon, authenticated;
revoke all on public.daily_task_attempts from public, anon, authenticated;
revoke all on public.earning_ledger from public, anon, authenticated;
revoke all on public.earning_security_flags from public, anon, authenticated;
revoke all on public.kyc_submissions from public, anon, authenticated;
revoke all on public.withdrawal_requests from public, anon, authenticated;
revoke all on public.site_presence from public, anon, authenticated;

grant select on public.earn_chat_settings to anon, authenticated;
grant select on public.profiles, public.chat_reward_sessions, public.daily_task_attempts,
  public.earning_ledger, public.kyc_submissions, public.withdrawal_requests to authenticated;

revoke all on function public._earn_chat_credit(uuid,text,text,bigint,bigint,jsonb) from public, anon, authenticated;
revoke all on function public._earn_chat_ensure_profile(uuid,text) from public, anon, authenticated;
revoke all on function public._earn_chat_prepare_day(uuid) from public, anon, authenticated;
revoke all on function public._earn_chat_state(uuid,text) from public, anon, authenticated;
grant execute on function public._earn_chat_credit(uuid,text,text,bigint,bigint,jsonb) to service_role;
grant execute on function public._earn_chat_ensure_profile(uuid,text) to service_role;
grant execute on function public._earn_chat_prepare_day(uuid) to service_role;
grant execute on function public._earn_chat_state(uuid,text) to service_role;

revoke execute on function public.admin_review_kyc(uuid,text,text) from public, anon;
revoke execute on function public.admin_review_withdrawal(uuid,text,text,text,bigint,timestamptz,text,boolean) from public, anon;
grant execute on function public.admin_review_kyc(uuid,text,text) to authenticated;
grant execute on function public.admin_review_withdrawal(uuid,text,text,text,bigint,timestamptz,text,boolean) to authenticated;

revoke execute on function public.claim_chat_message(uuid) from public, anon;
revoke execute on function public.claim_chat_share(uuid) from public, anon;
revoke execute on function public.claim_daily_reward(text) from public, anon;
revoke execute on function public.record_daily_share() from public, anon;
revoke execute on function public.request_withdrawal(text,text,text,bigint) from public, anon;
revoke execute on function public.submit_kyc_request() from public, anon;
grant execute on function public.claim_chat_message(uuid), public.claim_chat_share(uuid),
  public.claim_daily_reward(text), public.record_daily_share(),
  public.request_withdrawal(text,text,text,bigint), public.submit_kyc_request() to authenticated;

commit;
