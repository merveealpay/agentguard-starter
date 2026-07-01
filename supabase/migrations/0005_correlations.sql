-- Links a tool_call (MCP layer) to an edr_event (OS layer). Many-to-many: one call can map to
-- several OS effects, one OS event can match more than one call. basis records how the link was
-- made (strongest first) and confidence is 0..1. Written by the edr-bridge worker.
create table if not exists public.correlations (
  id uuid primary key default gen_random_uuid(),
  tool_call_id uuid not null references public.tool_calls(id) on delete cascade,
  edr_event_id uuid not null references public.edr_events(id) on delete cascade,
  basis text not null check (basis in ('pid_lineage','time_window','host_net')),
  confidence numeric not null check (confidence >= 0 and confidence <= 1),
  created_at timestamptz not null default now(),
  unique (tool_call_id, edr_event_id)
);

create index if not exists correlations_tool_call_idx on public.correlations (tool_call_id);
create index if not exists correlations_edr_event_idx on public.correlations (edr_event_id);

alter table public.correlations enable row level security;

drop policy if exists "correlations public read" on public.correlations;
create policy "correlations public read" on public.correlations for select using (true);

alter publication supabase_realtime add table public.correlations;
