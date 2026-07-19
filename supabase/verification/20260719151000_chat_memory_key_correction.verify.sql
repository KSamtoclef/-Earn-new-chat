-- Earn Chat Stage 8 chat correction verification.

select
  'blocking'::text as severity,
  'chat memory key uses text concatenation'::text as check_name,
  position('''recent_''+v_intent' in p.prosrc) = 0
    and position('''recent_'' + v_intent' in p.prosrc) = 0
    and (
      position('''recent_''||v_intent' in p.prosrc) > 0
      or position('''recent_'' || v_intent' in p.prosrc) > 0
    ) as passed,
  case
    when position('''recent_''+v_intent' in p.prosrc) > 0
      or position('''recent_'' + v_intent' in p.prosrc) > 0
      then 'invalid text addition remains'
    else 'valid text concatenation installed'
  end as observed,
  'valid text concatenation installed'::text as expected
from pg_proc p
where p.oid = to_regprocedure('public.earn_chat_send_message(uuid,text,text,text)')

union all

select
  'blocking',
  'chat RPC privilege boundary',
  has_function_privilege('authenticated','public.earn_chat_send_message(uuid,text,text,text)','EXECUTE')
    and not has_function_privilege('anon','public.earn_chat_send_message(uuid,text,text,text)','EXECUTE'),
  format(
    'authenticated=%s anon=%s',
    has_function_privilege('authenticated','public.earn_chat_send_message(uuid,text,text,text)','EXECUTE'),
    has_function_privilege('anon','public.earn_chat_send_message(uuid,text,text,text)','EXECUTE')
  ),
  'authenticated=t anon=f';
