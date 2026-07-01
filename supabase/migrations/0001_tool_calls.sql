create extension if not exists pgcrypto;

create table if not exists public.tool_calls (
  id uuid primary key default gen_random_uuid(),
  ts timestamptz not null default now(),
  session_id text not null,
  agent text not null,
  tool text not null,
  args jsonb not null default '{}'::jsonb,
  verdict text not null check (verdict in ('allow','deny','ask')),
  reason text,
  risk_score int check (risk_score between 0 and 10),
  owasp text,
  latency_ms int,
  upstream_status text,
  source text not null default 'demo'
);

create index if not exists tool_calls_ts_idx on public.tool_calls (ts desc);
create index if not exists tool_calls_session_idx on public.tool_calls (session_id);

alter table public.tool_calls enable row level security;

-- Public demo data: anyone may read. No client writes (service_role bypasses RLS).
drop policy if exists "tool_calls public read" on public.tool_calls;
create policy "tool_calls public read" on public.tool_calls for select using (true);

-- Stream inserts to the dashboard.
alter publication supabase_realtime add table public.tool_calls;
