-- Report state changes must be atomic with their audit record. Authenticated
-- admins use this RPC; no client can update reporter identity or timestamps.
drop policy if exists reports_admin_update on public.user_reports;
revoke update on public.user_reports from authenticated;

create or replace function public.admin_set_report_state(
  target_report_id uuid,
  next_state text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if next_state is null or next_state not in ('open', 'reviewing', 'closed') then
    raise exception 'invalid_report_state' using errcode = '22023';
  end if;

  update public.user_reports
  set state = next_state, updated_at = now()
  where id = target_report_id;
  if not found then
    raise exception 'report_not_found' using errcode = 'P0002';
  end if;

  insert into public.admin_audit_logs(actor_id, action, target_type, target_id)
  values (auth.uid(), 'report_status_changed', 'report', target_report_id);
end;
$$;
revoke all on function public.admin_set_report_state(uuid, text) from public;
grant execute on function public.admin_set_report_state(uuid, text) to authenticated;
