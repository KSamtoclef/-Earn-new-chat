-- Earn Chat Stage 6 wallet reconciliation.
-- Held and paid USD withdrawal entries must reduce the displayed available balance.

begin;

create or replace function public.earn_chat_get_wallet_state()
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid(); v_date date:=(now() at time zone 'Africa/Lagos')::date; v_result jsonb;
begin
 if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
 select jsonb_build_object(
  'earning_currency','USD','country_code',p.country_code,'preferred_currency',p.preferred_currency,
  'balances',jsonb_build_object(
    'USD',coalesce((select sum(amount) from public.earning_ledger where user_id=v_uid and currency_code='USD' and status in('credited','adjustment','refunded','held','paid')),0),
    'NGN',coalesce(p.balance,0)),
  'reserved_withdrawal_minor',abs(coalesce((select sum(amount) from public.earning_ledger where user_id=v_uid and currency_code='USD' and status='held' and reward_type='withdrawal_hold'),0)),
  'today_usd_minor',coalesce((select sum(amount) from public.earning_ledger where user_id=v_uid and currency_code='USD' and earning_date=v_date and status in('credited','adjustment','refunded') and amount>0),0),
  'settings',to_jsonb(s)
 ) into v_result from public.profiles p cross join public.earn_chat_currency_settings s where p.id=v_uid and s.id=1;
 return v_result;
end; $$;

revoke all on function public.earn_chat_get_wallet_state() from public,anon;
grant execute on function public.earn_chat_get_wallet_state() to authenticated;

commit;
