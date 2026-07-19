-- Earn Chat Stage 5B: one inline sponsored opportunity lifecycle.
-- Lifecycle: eligible -> impressed -> clicked -> returned -> verified -> credited.

begin;

alter table public.earn_chat_sponsored_offers
  add column if not exists reward_minor bigint not null default 0;
alter table public.earn_chat_sponsored_offers
  drop constraint if exists earn_chat_sponsored_offers_reward_minor_check;
alter table public.earn_chat_sponsored_offers
  add constraint earn_chat_sponsored_offers_reward_minor_check
  check (reward_minor >= 0);

alter table public.earn_chat_sponsored_opportunities
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists earn_chat_sponsored_thread_offer_day_key
  on public.earn_chat_sponsored_opportunities(user_id, thread_id, offer_id, opportunity_date)
  where thread_id is not null;

create index if not exists earn_chat_sponsored_offer_delivery_idx
  on public.earn_chat_sponsored_offers(placement, active, starts_at, ends_at, minimum_meaningful_replies);

create or replace function public.earn_chat_get_inline_sponsored(p_thread_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_uid uuid := auth.uid();
  v_date date := (now() at time zone 'Africa/Lagos')::date;
  v_thread public.earn_chat_threads%rowtype;
  v_offer public.earn_chat_sponsored_offers%rowtype;
  v_opportunity public.earn_chat_sponsored_opportunities%rowtype;
  v_key text;
  v_cap bigint;
  v_today bigint;
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode='28000';
  end if;

  select * into v_thread
  from public.earn_chat_threads
  where id=p_thread_id and user_id=v_uid;

  if not found or v_thread.status not in ('active','paused') then
    return null;
  end if;

  select case when coalesce(p.has_withdrawn,false)
         then s.returning_daily_cap_minor else s.standard_daily_cap_minor end
  into v_cap
  from public.profiles p cross join public.earn_chat_currency_settings s
  where p.id=v_uid and s.id=1;
  select coalesce(sum(amount),0) into v_today
  from public.earning_ledger
  where user_id=v_uid and currency_code='USD' and earning_date=v_date
    and status in ('credited','adjustment','refunded');
  if v_today>=v_cap then return null; end if;

  select * into v_opportunity
  from public.earn_chat_sponsored_opportunities
  where user_id=v_uid
    and thread_id=v_thread.id
    and opportunity_date=v_date
    and status not in ('expired')
  order by created_at desc
  limit 1;

  if found then
    select * into v_offer
    from public.earn_chat_sponsored_offers
    where id=v_opportunity.offer_id;
  else
    select * into v_offer
    from public.earn_chat_sponsored_offers o
    where o.active
      and o.placement='inline_chat'
      and o.reward_minor>0
      and (o.starts_at is null or o.starts_at<=now())
      and (o.ends_at is null or o.ends_at>now())
      and v_thread.meaningful_message_count>=o.minimum_meaningful_replies
      and not exists (
        select 1
        from public.earn_chat_sponsored_opportunities used
        where used.user_id=v_uid
          and used.offer_id=o.id
          and used.opportunity_date=v_date
          and used.status in ('clicked','returned','verified','credited')
      )
    order by md5(v_uid::text||v_date::text||o.offer_key),o.id
    limit 1;

    if not found then return null; end if;

    v_key := 'inline:'||v_date::text||':'||v_thread.id::text||':'||v_offer.offer_key;
    insert into public.earn_chat_sponsored_opportunities(
      user_id,offer_id,thread_id,opportunity_date,status,idempotency_key
    ) values (
      v_uid,v_offer.id,v_thread.id,v_date,'available',v_key
    )
    on conflict(user_id,idempotency_key) do update
      set updated_at=public.earn_chat_sponsored_opportunities.updated_at
    returning * into v_opportunity;
  end if;

  if v_offer.id is null or not v_offer.active
     or (v_offer.starts_at is not null and v_offer.starts_at>now())
     or (v_offer.ends_at is not null and v_offer.ends_at<=now()) then
    return null;
  end if;

  return jsonb_build_object(
    'opportunity_id',v_opportunity.id,
    'status',v_opportunity.status,
    'title',v_offer.title,
    'description',v_offer.description,
    'reward_minor',v_offer.reward_minor,
    'currency_code','USD',
    'minimum_seconds_away',v_offer.minimum_seconds_away,
    'can_open',v_opportunity.status in ('available','impressed'),
    'can_verify',v_opportunity.status in ('returned','verified','credited')
  );
end;
$$;

create or replace function public.earn_chat_record_sponsored_impression(p_opportunity_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare v_uid uuid:=auth.uid(); v_row public.earn_chat_sponsored_opportunities%rowtype;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
  update public.earn_chat_sponsored_opportunities
  set status=case when status='available' then 'impressed' else status end,
      impressed_at=coalesce(impressed_at,now()),updated_at=now()
  where id=p_opportunity_id and user_id=v_uid
    and status in ('available','impressed','clicked','returned','verified','credited')
  returning * into v_row;
  if not found then raise exception 'Sponsored opportunity unavailable'; end if;
  return jsonb_build_object('opportunity_id',v_row.id,'status',v_row.status);
end;
$$;

create or replace function public.earn_chat_begin_sponsored(p_opportunity_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_uid uuid:=auth.uid();
  v_row public.earn_chat_sponsored_opportunities%rowtype;
  v_offer public.earn_chat_sponsored_offers%rowtype;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
  select * into v_row from public.earn_chat_sponsored_opportunities
  where id=p_opportunity_id and user_id=v_uid for update;
  if not found or v_row.status not in ('available','impressed') then
    raise exception 'Sponsored opportunity cannot be opened';
  end if;
  select * into v_offer from public.earn_chat_sponsored_offers
  where id=v_row.offer_id and active
    and (starts_at is null or starts_at<=now())
    and (ends_at is null or ends_at>now());
  if not found then raise exception 'Sponsored offer is inactive'; end if;
  if v_offer.destination_url !~ '^https://[^[:space:]]+$' then
    raise exception 'Sponsored destination is invalid';
  end if;
  update public.earn_chat_sponsored_opportunities
  set status='clicked',impressed_at=coalesce(impressed_at,now()),clicked_at=now(),updated_at=now()
  where id=v_row.id;
  return jsonb_build_object(
    'opportunity_id',v_row.id,'status','clicked','destination_url',v_offer.destination_url,
    'minimum_seconds_away',v_offer.minimum_seconds_away
  );
end;
$$;

create or replace function public.earn_chat_record_sponsored_return(p_opportunity_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_uid uuid:=auth.uid();
  v_row public.earn_chat_sponsored_opportunities%rowtype;
  v_minimum integer;
  v_elapsed integer;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
  select o,f.minimum_seconds_away into v_row,v_minimum
  from public.earn_chat_sponsored_opportunities o
  join public.earn_chat_sponsored_offers f on f.id=o.offer_id
  where o.id=p_opportunity_id and o.user_id=v_uid for update of o;
  if not found or v_row.status<>'clicked' or v_row.clicked_at is null then
    raise exception 'Sponsored return is unavailable';
  end if;
  v_elapsed:=extract(epoch from (now()-v_row.clicked_at))::integer;
  if v_elapsed<v_minimum then
    raise exception 'Sponsored activity is not ready for verification';
  end if;
  update public.earn_chat_sponsored_opportunities
  set status='returned',returned_at=now(),updated_at=now()
  where id=v_row.id;
  return jsonb_build_object('opportunity_id',v_row.id,'status','returned','elapsed_seconds',v_elapsed);
end;
$$;

create or replace function public.earn_chat_verify_sponsored(p_opportunity_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_uid uuid:=auth.uid();
  v_date date:=(now() at time zone 'Africa/Lagos')::date;
  v_row public.earn_chat_sponsored_opportunities%rowtype;
  v_offer public.earn_chat_sponsored_offers%rowtype;
  v_credit bigint:=0;
  v_ledger uuid;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode='28000'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text||':'||p_opportunity_id::text,0));
  select * into v_row from public.earn_chat_sponsored_opportunities
  where id=p_opportunity_id and user_id=v_uid for update;
  if not found then raise exception 'Sponsored opportunity unavailable'; end if;
  if v_row.status='credited' then
    return jsonb_build_object('opportunity_id',v_row.id,'status','credited','credited_minor',0,'duplicate',true);
  end if;
  if v_row.status not in ('returned','verified') or v_row.returned_at is null then
    raise exception 'Sponsored activity has not been returned';
  end if;
  if v_row.opportunity_date<>v_date then raise exception 'Sponsored opportunity has expired'; end if;
  select * into v_offer from public.earn_chat_sponsored_offers where id=v_row.offer_id;
  if not found or v_offer.reward_minor<=0 then raise exception 'Sponsored reward is unavailable'; end if;

  update public.earn_chat_sponsored_opportunities
  set status='verified',verified_at=coalesce(verified_at,now()),updated_at=now()
  where id=v_row.id;

  v_credit:=earn_chat_private.append_usd_entry(
    v_uid,'usd:sponsored:'||v_row.id::text,'sponsored_activity',v_offer.reward_minor,
    'earn_chat_sponsored_opportunity',v_row.id,
    jsonb_build_object('offer_key',v_offer.offer_key,'thread_id',v_row.thread_id)
  );

  select id into v_ledger from public.earning_ledger
  where user_id=v_uid and event_key='usd:sponsored:'||v_row.id::text and currency_code='USD';

  update public.earn_chat_sponsored_opportunities
  set status='credited',credited_ledger_id=v_ledger,updated_at=now()
  where id=v_row.id and v_ledger is not null;

  if v_ledger is not null then
    update public.earn_chat_daily_goals g
    set progress=least(g.target,g.progress+1),
        status=case when g.progress+1>=g.target then 'completed' else g.status end,
        completed_at=case when g.progress+1>=g.target then coalesce(g.completed_at,now()) else g.completed_at end
    from public.earn_chat_goal_templates gt
    where g.template_id=gt.id and g.user_id=v_uid and g.goal_date=v_date
      and gt.goal_type='sponsored' and g.status='active';
  end if;

  return jsonb_build_object(
    'opportunity_id',v_row.id,
    'status',case when v_ledger is not null then 'credited' else 'verified' end,
    'credited_minor',v_credit,'currency_code','USD','duplicate',false
  );
end;
$$;

revoke all on function public.earn_chat_get_inline_sponsored(uuid) from public,anon;
revoke all on function public.earn_chat_record_sponsored_impression(uuid) from public,anon;
revoke all on function public.earn_chat_begin_sponsored(uuid) from public,anon;
revoke all on function public.earn_chat_record_sponsored_return(uuid) from public,anon;
revoke all on function public.earn_chat_verify_sponsored(uuid) from public,anon;
grant execute on function public.earn_chat_get_inline_sponsored(uuid) to authenticated;
grant execute on function public.earn_chat_record_sponsored_impression(uuid) to authenticated;
grant execute on function public.earn_chat_begin_sponsored(uuid) to authenticated;
grant execute on function public.earn_chat_record_sponsored_return(uuid) to authenticated;
grant execute on function public.earn_chat_verify_sponsored(uuid) to authenticated;

commit;
