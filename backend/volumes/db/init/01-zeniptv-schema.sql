-- ============================================================================
-- Zen IPTV — domain schema (accounts via 8-char codes, IPTV sources, devices)
-- Runs once on first DB init (mounted into /docker-entrypoint-initdb.d).
-- Lives in schema `zeniptv`; exposed to PostgREST so the app/admin can use it.
-- ============================================================================

create schema if not exists zeniptv;
grant usage on schema zeniptv to anon, authenticated, service_role;

-- --- 8-char uppercase alphanumeric code generator (no ambiguous chars) -------
-- Excludes 0/O/1/I to avoid user confusion. 32^8 ≈ 1.1e12 combinations.
create or replace function zeniptv.gen_access_code()
returns text language plpgsql as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i int;
begin
  for i in 1..8 loop
    result := result || substr(alphabet, 1 + floor(random()*length(alphabet))::int, 1);
  end loop;
  return result;
end;
$$;

-- --- accounts: one row = one access code = one customer --------------------
create table if not exists zeniptv.accounts (
  id            uuid primary key default gen_random_uuid(),
  access_code   text unique not null default zeniptv.gen_access_code()
                  check (access_code ~ '^[A-Z2-9]{8}$'),
  label         text,                              -- human note (customer name)
  status        text not null default 'active'
                  check (status in ('active','blocked','expired')),
  max_devices   int  not null default 1 check (max_devices >= 1),
  expires_at    timestamptz,                       -- null = never expires
  -- optional link to a Supabase auth user (filled when app logs in with code)
  auth_user_id  uuid,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists accounts_status_idx on zeniptv.accounts(status);

-- --- iptv_sources: per-account Xtream portals / M3U playlists --------------
create table if not exists zeniptv.iptv_sources (
  id            uuid primary key default gen_random_uuid(),
  account_id    uuid not null references zeniptv.accounts(id) on delete cascade,
  kind          text not null check (kind in ('xtream','m3u')),
  name          text not null default 'My Playlist',
  -- xtream fields
  server_url    text,                              -- e.g. http://portal:port
  username      text,
  password      text,
  -- m3u field
  m3u_url       text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  -- shape validation: xtream needs server+user+pass; m3u needs url
  check ( (kind='xtream' and server_url is not null and username is not null and password is not null)
       or (kind='m3u'    and m3u_url is not null) )
);
create index if not exists iptv_sources_account_idx on zeniptv.iptv_sources(account_id);

-- --- devices: enforce per-account device limit -----------------------------
create table if not exists zeniptv.devices (
  id            uuid primary key default gen_random_uuid(),
  account_id    uuid not null references zeniptv.accounts(id) on delete cascade,
  device_id     text not null,                     -- stable device identifier from app
  device_name   text,
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  unique (account_id, device_id)
);
create index if not exists devices_account_idx on zeniptv.devices(account_id);

-- --- keep updated_at fresh --------------------------------------------------
create or replace function zeniptv.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end; $$;
drop trigger if exists trg_accounts_touch on zeniptv.accounts;
create trigger trg_accounts_touch before update on zeniptv.accounts
  for each row execute function zeniptv.touch_updated_at();

-- --- helper: redeem a code (used by the app at login) -----------------------
-- Returns the account if code is valid + active + not expired + under device cap.
-- Registers/refreshes the device. SECURITY DEFINER so anon can call it safely.
create or replace function zeniptv.redeem_access_code(
  p_code text, p_device_id text, p_device_name text default null)
returns table (out_account_id uuid, out_status text, out_max_devices int, out_device_count int)
language plpgsql security definer set search_path = zeniptv as $$
declare a zeniptv.accounts; cnt int;
begin
  select * into a from zeniptv.accounts where access_code = upper(p_code);
  if not found then raise exception 'INVALID_CODE' using errcode='P0001'; end if;
  if a.status <> 'active' then raise exception 'ACCOUNT_%', upper(a.status) using errcode='P0002'; end if;
  if a.expires_at is not null and a.expires_at < now() then
     update zeniptv.accounts set status='expired' where id=a.id;
     raise exception 'ACCOUNT_EXPIRED' using errcode='P0003';
  end if;
  -- register/refresh device (qualify columns to avoid collision with OUT names)
  insert into zeniptv.devices(account_id, device_id, device_name)
    values (a.id, p_device_id, p_device_name)
    on conflict (account_id, device_id)
    do update set last_seen_at = now(),
                  device_name = coalesce(excluded.device_name, zeniptv.devices.device_name);
  select count(*) into cnt from zeniptv.devices d where d.account_id = a.id;
  if cnt > a.max_devices then
     raise exception 'DEVICE_LIMIT_REACHED' using errcode='P0004';
  end if;
  return query select a.id, a.status, a.max_devices, cnt;
end; $$;

-- --- Row Level Security ----------------------------------------------------
alter table zeniptv.accounts     enable row level security;
alter table zeniptv.iptv_sources enable row level security;
alter table zeniptv.devices      enable row level security;

-- service_role (our admin backend) bypasses RLS automatically.
-- authenticated users may read ONLY their own linked account + sources.
drop policy if exists acct_self_read on zeniptv.accounts;
create policy acct_self_read on zeniptv.accounts
  for select to authenticated using (auth_user_id = auth.uid());
drop policy if exists src_self_read on zeniptv.iptv_sources;
create policy src_self_read on zeniptv.iptv_sources
  for select to authenticated using (
    account_id in (select id from zeniptv.accounts where auth_user_id = auth.uid()));
drop policy if exists dev_self_read on zeniptv.devices;
create policy dev_self_read on zeniptv.devices
  for select to authenticated using (
    account_id in (select id from zeniptv.accounts where auth_user_id = auth.uid()));

-- public wrapper so PostgREST exposes it at /rest/v1/rpc/redeem_access_code
-- (PostgREST resolves rpc against the first exposed schema = public).
create or replace function public.redeem_access_code(
  p_code text, p_device_id text, p_device_name text default null)
returns table (account_id uuid, status text, max_devices int, device_count int)
language sql security definer set search_path = public, zeniptv as $$
  select out_account_id, out_status, out_max_devices, out_device_count
  from zeniptv.redeem_access_code(p_code, p_device_id, p_device_name);
$$;
grant execute on function public.redeem_access_code(text,text,text) to anon, authenticated, service_role;

-- expose redeem function to anon (gated internally by the code itself)
grant execute on function zeniptv.redeem_access_code(text,text,text) to anon, authenticated, service_role;
grant execute on function zeniptv.gen_access_code() to service_role;
grant select on all tables in schema zeniptv to authenticated;
grant all on all tables in schema zeniptv to service_role;

-- --- seed one demo account so the stack is testable immediately -------------
insert into zeniptv.accounts(label, max_devices) values ('demo (auto-seed)', 2)
  on conflict do nothing;
