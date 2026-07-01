create extension if not exists pgcrypto;

-- Normalized OS-layer telemetry ingested from an EDR (Wazuh) by the edr-bridge worker.
-- EDR-agnostic shape; the gateway never writes here. Correlated to tool_calls via the
-- correlations table (see 0005). source+external_id is the idempotent ingest key.
create table if not exists public.edr_events (
  id uuid primary key default gen_random_uuid(),
  ts timestamptz not null,                 -- event time as reported by the EDR
  ingested_at timestamptz not null default now(),
  source text not null default 'wazuh',
  external_id text,                        -- EDR-native id (Wazuh alert id); dedup key
  host text not null,
  category text not null check (category in ('process','file','network','other')),
  -- process
  pid int,
  ppid int,
  process_name text,
  process_path text,
  cmdline text,
  -- file
  file_path text,
  file_op text,
  -- network
  dst_ip text,
  dst_port int,
  direction text,
  -- EDR metadata
  rule_id text,
  rule_level int,
  rule_desc text,
  mitre text[],
  session_id text,
  raw jsonb not null default '{}'::jsonb
);

create index if not exists edr_events_ts_idx on public.edr_events (ts desc);
create index if not exists edr_events_host_ts_idx on public.edr_events (host, ts desc);
create index if not exists edr_events_host_pid_idx on public.edr_events (host, pid);
-- Idempotent ingest: at most one row per EDR-native id per source.
create unique index if not exists edr_events_source_external_idx
  on public.edr_events (source, external_id)
  where external_id is not null;

alter table public.edr_events enable row level security;

-- Demo posture: public read (mirrors tool_calls). NOTE: OS telemetry is sensitive — a real
-- deployment must restrict this. No client writes (service_role bypasses RLS).
drop policy if exists "edr_events public read" on public.edr_events;
create policy "edr_events public read" on public.edr_events for select using (true);

-- Stream inserts to the dashboard.
alter publication supabase_realtime add table public.edr_events;
