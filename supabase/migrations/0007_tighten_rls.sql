-- Tighten reads from public (anon) to authenticated-only, for the login-gated live deploy.
-- The public keyless demo reads nothing from Supabase, so it is unaffected. Writes go through the
-- service_role key (bypasses RLS), so the gateway + ingest endpoint are unaffected. Realtime respects
-- RLS via the connection JWT, so logged-in console users still receive inserts.

drop policy if exists "tool_calls public read" on public.tool_calls;
create policy "tool_calls auth read" on public.tool_calls
  for select to authenticated using (true);

drop policy if exists "pending_calls public read" on public.pending_calls;
create policy "pending_calls auth read" on public.pending_calls
  for select to authenticated using (true);

drop policy if exists "edr_events public read" on public.edr_events;
create policy "edr_events auth read" on public.edr_events
  for select to authenticated using (true);

drop policy if exists "correlations public read" on public.correlations;
create policy "correlations auth read" on public.correlations
  for select to authenticated using (true);
