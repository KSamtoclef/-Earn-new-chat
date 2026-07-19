-- Earn Chat Stage 8 correction: use PostgreSQL text concatenation in chat memory keys.

begin;

do $$
declare
  v_function regprocedure := to_regprocedure('public.earn_chat_send_message(uuid,text,text,text)');
  v_before text;
  v_after text;
begin
  if v_function is null then
    raise exception 'earn_chat_send_message(uuid,text,text,text) does not exist';
  end if;

  select pg_get_functiondef(v_function) into v_before;
  v_after := replace(v_before, '''recent_''+v_intent', '''recent_''||v_intent');
  v_after := replace(v_after, '''recent_'' + v_intent', '''recent_'' || v_intent');

  if v_after = v_before then
    if position('''recent_''||v_intent' in v_before) > 0
       or position('''recent_'' || v_intent' in v_before) > 0 then
      return;
    end if;
    raise exception 'Expected defective chat memory expression was not found';
  end if;

  execute v_after;
end;
$$;

revoke all on function public.earn_chat_send_message(uuid,text,text,text) from public,anon;
grant execute on function public.earn_chat_send_message(uuid,text,text,text) to authenticated;

commit;
