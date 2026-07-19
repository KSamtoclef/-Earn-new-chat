-- Emergency code/permission rollback for Stage 3A.
-- Data corrections and created profiles are intentionally retained to avoid user-data loss.
begin;

drop trigger if exists earn_chat_bootstrap_user on auth.users;
drop function if exists earn_chat_private.bootstrap_auth_user();

drop policy if exists "users read own secure profile" on public.profiles;
create policy "Users can view own profile" on public.profiles for select to public using (auth.uid()=id);
create policy "Users can insert own profile" on public.profiles for insert to public with check (auth.uid()=id);
create policy "Users can update own profile" on public.profiles for update to public using (auth.uid()=id);

grant select,insert,update on public.profiles to authenticated;
grant execute on function public._earn_chat_credit(uuid,text,text,bigint,bigint,jsonb) to authenticated;
grant execute on function public._earn_chat_ensure_profile(uuid,text) to authenticated;
grant execute on function public._earn_chat_prepare_day(uuid) to authenticated;
grant execute on function public._earn_chat_state(uuid,text) to authenticated;

commit;
