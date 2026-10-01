-- Admins may inspect SOS metadata, but state changes must pass through the
-- audited SECURITY DEFINER RPC rather than a broad table UPDATE policy.
drop policy if exists sos_admin_update on public.sos_events;
