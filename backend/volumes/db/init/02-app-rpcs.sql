-- ============================================================================
-- Zen IPTV — app-facing RPCs (additive, idempotent). Applied after
-- 01-zeniptv-schema.sql. Safe to re-run (create or replace only).
--
-- Adds:
--   1. get_sources_for_code(code, device_id) — returns the account's active
--      IPTV sources, gated by a valid+active code AND a registered device.
--      Needed because anon is RLS-blocked from reading zeniptv.iptv_sources.
--   2. Hardened redeem_access_code — checks the device cap BEFORE inserting a
--      new device, so a rejected device never gets a row (no reliance on tx
--      rollback) and an already-registered device can always re-redeem.
-- ============================================================================

-- --- 1. get_sources_for_code -----------------------------------------------
-- Returns the active sources for the account behind <code>, but ONLY if
-- <device_id> is already registered to that account (i.e. it previously
-- redeemed successfully). SECURITY DEFINER so anon can call it; the code +
-- registered-device pair is the gate. Passwords / credential-bearing m3u_url
-- are returned here intentionally — the app needs them to talk to the portal,
-- and exposure is limited to the holder of a valid code on a registered device
-- (acceptable for this self-hosted, owner-operated deployment).
create or replace function public.get_sources_for_code(
  p_code text, p_device_id text)
returns setof zeniptv.iptv_sources
language plpgsql security definer set search_path = public, zeniptv as $$
declare a zeniptv.accounts;
begin
  select * into a from zeniptv.accounts where access_code = upper(p_code);
  if not found or a.status <> 'active' then
    raise exception 'INVALID_OR_INACTIVE' using errcode='P0005';
  end if;
  if a.expires_at is not null and a.expires_at < now() then
    raise exception 'INVALID_OR_INACTIVE' using errcode='P0005';
  end if;
  if not exists (select 1 from zeniptv.devices d
                 where d.account_id = a.id and d.device_id = p_device_id) then
    raise exception 'DEVICE_NOT_REGISTERED' using errcode='P0006';
  end if;
  return query
    select * from zeniptv.iptv_sources s
    where s.account_id = a.id and s.is_active = true
    order by s.created_at;
end; $$;

grant execute on function public.get_sources_for_code(text,text)
  to anon, authenticated, service_role;

-- --- 2. Hardened redeem_access_code ----------------------------------------
-- Difference vs 01-schema version: count devices and decide the cap BEFORE
-- inserting. A new device that would exceed max_devices is rejected with no
-- row written; an already-registered device always refreshes (never blocked).
create or replace function zeniptv.redeem_access_code(
  p_code text, p_device_id text, p_device_name text default null)
returns table (out_account_id uuid, out_status text, out_max_devices int, out_device_count int)
language plpgsql security definer set search_path = zeniptv as $$
declare a zeniptv.accounts; cnt int; already bool;
begin
  select * into a from zeniptv.accounts where access_code = upper(p_code);
  if not found then raise exception 'INVALID_CODE' using errcode='P0001'; end if;
  if a.status <> 'active' then raise exception 'ACCOUNT_%', upper(a.status) using errcode='P0002'; end if;
  if a.expires_at is not null and a.expires_at < now() then
     update zeniptv.accounts set status='expired' where id=a.id;
     raise exception 'ACCOUNT_EXPIRED' using errcode='P0003';
  end if;

  select exists(select 1 from zeniptv.devices d
                where d.account_id = a.id and d.device_id = p_device_id) into already;
  select count(*) into cnt from zeniptv.devices d where d.account_id = a.id;

  -- New device that would exceed the cap: reject BEFORE inserting.
  if not already and cnt >= a.max_devices then
     raise exception 'DEVICE_LIMIT_REACHED' using errcode='P0004';
  end if;

  insert into zeniptv.devices(account_id, device_id, device_name)
    values (a.id, p_device_id, p_device_name)
    on conflict (account_id, device_id)
    do update set last_seen_at = now(),
                  device_name = coalesce(excluded.device_name, zeniptv.devices.device_name);

  if not already then cnt := cnt + 1; end if;
  return query select a.id, a.status, a.max_devices, cnt;
end; $$;

grant execute on function zeniptv.redeem_access_code(text,text,text)
  to anon, authenticated, service_role;

-- Keep the public wrapper in sync (signature unchanged; re-create defensively).
create or replace function public.redeem_access_code(
  p_code text, p_device_id text, p_device_name text default null)
returns table (account_id uuid, status text, max_devices int, device_count int)
language sql security definer set search_path = public, zeniptv as $$
  select out_account_id, out_status, out_max_devices, out_device_count
  from zeniptv.redeem_access_code(p_code, p_device_id, p_device_name);
$$;
grant execute on function public.redeem_access_code(text,text,text)
  to anon, authenticated, service_role;

-- --- 3. create_access_code (self-service registration) ---------------------
-- A user without a code can mint one by supplying a profile label, so the
-- admin can tell who owns each code. The new account is active with the
-- default max_devices and NO IPTV source — it is unusable for streaming until
-- an admin assigns a source, which is the intended throttle on open self-
-- registration. Returns the freshly generated 8-char code.
create or replace function public.create_access_code(p_label text)
returns table (access_code text)
language plpgsql security definer set search_path = public, zeniptv as $$
declare v_label text := nullif(btrim(coalesce(p_label, '')), ''); v_code text;
begin
  if v_label is null then
    raise exception 'LABEL_REQUIRED' using errcode='P0007';
  end if;
  v_label := left(v_label, 80);
  insert into zeniptv.accounts (label) values (v_label)
    returning zeniptv.accounts.access_code into v_code;
  return query select v_code;
end; $$;

grant execute on function public.create_access_code(text)
  to anon, authenticated, service_role;
