-- Correlation anchors on tool_calls: the host the call ran on and the upstream MCP server PID the
-- gateway spawned. The edr-bridge matches OS telemetry to this PID's process subtree (and host).
-- Nullable + backward-compatible: existing rows and demo-source rows simply leave them null.
alter table public.tool_calls add column if not exists host text;
alter table public.tool_calls add column if not exists upstream_pid int;

create index if not exists tool_calls_host_pid_idx on public.tool_calls (host, upstream_pid);
