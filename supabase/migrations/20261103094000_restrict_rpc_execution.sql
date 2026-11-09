revoke all on function public.travel_bootstrap(), public.travel_snapshot(), public.travel_action(text,jsonb) from anon;
revoke all on all functions in schema private from anon, authenticated;
grant execute on function private.member(uuid,uuid) to authenticated;
grant execute on function public.travel_bootstrap(), public.travel_snapshot(), public.travel_action(text,jsonb) to authenticated;
