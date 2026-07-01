-- Ask-queue: calls the gateway holds for human approval (M2).
create table if not exists public.pending_calls (
  id uuid primary key default gen_random_uuid(),
  ts timestamptz not null default now(),
  session_id text not null,
  agent text not null,
  tool text not null,
  args jsonb not null default '{}'::jsonb,
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','denied')),
  resolved_at timestamptz
);

create index if not exists pending_calls_status_idx on public.pending_calls (status, ts desc);

alter table public.pending_calls enable row level security;

-- Dashboard reads the queue (anon); status is updated server-side via the service role.
drop policy if exists "pending_calls public read" on public.pending_calls;
create policy "pending_calls public read" on public.pending_calls for select using (true);

alter publication supabase_realtime add table public.pending_calls;
