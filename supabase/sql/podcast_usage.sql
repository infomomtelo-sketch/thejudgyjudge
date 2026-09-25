-- judgy-podcast daily usage caps. Run once in the Supabase SQL editor (project dmemzljerldzeiwqfxzp).
-- Stores only: UTC day, a key ('global' or 'ip:<HMAC-SHA-256 hex>'), and a count. No raw IPs, no topics.

create table if not exists public.podcast_usage (
  day   date    not null,
  key   text    not null,
  count integer not null default 0,
  primary key (day, key)
);

-- RLS on with no policies: anon/authenticated can't read or write. Only the service role (the edge function) can.
alter table public.podcast_usage enable row level security;
revoke all on table public.podcast_usage from anon, authenticated;

-- Atomically checks the per-IP and global caps for p_day and, only if both pass, counts one episode against each.
-- Returns 'ok', 'ip' (per-IP cap hit) or 'global' (global cap hit). Locks global then IP row, always in that order.
create or replace function public.podcast_try_consume(
  p_day date, p_ip_key text, p_ip_limit integer, p_global_limit integer
) returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  g_count  integer;
  ip_count integer;
begin
  insert into public.podcast_usage (day, key, count)
  values (p_day, 'global', 0), (p_day, p_ip_key, 0)
  on conflict (day, key) do nothing;

  select count into g_count  from public.podcast_usage where day = p_day and key = 'global' for update;
  select count into ip_count from public.podcast_usage where day = p_day and key = p_ip_key for update;

  if ip_count >= p_ip_limit then return 'ip'; end if;
  if g_count  >= p_global_limit then return 'global'; end if;

  update public.podcast_usage set count = count + 1
  where day = p_day and key in ('global', p_ip_key);
  return 'ok';
end;
$$;

revoke all on function public.podcast_try_consume(date, text, integer, integer) from public, anon, authenticated;
grant execute on function public.podcast_try_consume(date, text, integer, integer) to service_role;

-- Optional housekeeping: keep ~30 days of counters. Run by hand or from pg_cron if you have it enabled.
-- delete from public.podcast_usage where day < current_date - 30;
