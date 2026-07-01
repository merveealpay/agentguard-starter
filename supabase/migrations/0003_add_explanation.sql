-- AI layer (M3): a plain-language risk explanation written back onto each tool call.
alter table public.tool_calls add column if not exists explanation text;
