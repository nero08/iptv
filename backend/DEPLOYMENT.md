# Deployment record — Deko IPTV backend

**Deployed:** 2026-06-01 · **Host:** 51.75.77.132 (`wowdev`, user ubuntu) · **Path:** `/opt/iptv-backend`
**Public base:** http://iptv.sarlnsi.ovh:4500 (single port, Kong gateway)

## Architecture

Self-hosted **Supabase** (so the Deko IPTV app can eventually point here) + a custom
**FastAPI admin** for 8-char access-code accounts and per-account IPTV sources.
All traffic via Kong on host port **4500**; Postgres is internal only (127.0.0.1:5433 for SSH-tunnel admin).

| Path | Service | Purpose |
|------|---------|---------|
| `/auth/v1/*` | GoTrue | app login (Supabase auth) |
| `/rest/v1/*` | PostgREST | data API (`zeniptv` schema), key-auth + ACL |
| `/admin`, `/admin/*` | FastAPI | account/IPTV admin UI + JSON API |
| `/deko-iptv.apk` | FastAPI (admin) | **public Deko IPTV APK download** (no auth) |
| `/` | Studio | generic DB admin UI (basic-auth) |

## Live verification (external, against http://iptv.sarlnsi.ovh:4500)

| Check | Result |
|-------|--------|
| `GET /auth/v1/health` | **200** |
| `GET /admin/healthz` | **200** |
| `GET /admin/login` (UI) | **200** |
| `GET /rest/v1/` no apikey | **401** (rejected) |
| `GET /rest/v1/` anon key | **200** |
| `GET /` Studio no auth | **401** |
| `GET /` Studio basic-auth | **200** |
| Create account (admin API, Bearer) | 8-char code e.g. `H7TKVTAN` |
| `GET /admin/api/accounts` no token | **401** (rejected) |
| `rpc/redeem_access_code` device A | `active, device_count=1` |
| same device A again | idempotent, `device_count=1` |
| device B over max_devices=1 | `DEVICE_LIMIT_REACHED` |
| blocked account | `ACCOUNT_BLOCKED` |
| invalid code | `INVALID_CODE` |

7/7 containers running: db, auth, rest, meta, studio, kong, admin.

## Domain model (`zeniptv` schema)

- `accounts` — 1 row = 1 **8-char uppercase code** (`gen_access_code()`, excludes 0/O/1/I),
  `status` active/blocked/expired, `max_devices`, `expires_at`.
- `iptv_sources` — per-account Xtream portals or M3U playlists.
- `devices` — registered devices; enforces `max_devices`.
- `redeem_access_code(code, device_id, name)` — app login RPC: validates code/status/expiry/device cap, registers device.

## Operate

```bash
ssh wowdev
cd /opt/iptv-backend
./deploy.sh             # idempotent: render kong cfg, align roles, apply schema, start, health-probe
docker compose ps
docker compose logs -f admin
docker compose down     # stop (keeps data volume zeniptv_zeniptv-db-data)
```

Credentials live in `/opt/iptv-backend/.env` and `CREDENTIALS.txt` (server-only, git-ignored).
Admin UI + Studio login: `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`.

## Gotchas resolved during deploy

- `supabase_admin`/`authenticator`/`auth_admin` passwords are force-aligned to `POSTGRES_PASSWORD` in deploy step 3a (image init sets them differently).
- Kong 3.9.1 runs as non-root → cannot write `/home/kong/kong.yml`. We render the declarative
  config locally with `envsubst` (`kong.generated.yml`) and mount it read-only; no in-container render.
- Only 4 vars are substituted into kong config; everything else is literal.

## App download (Deko IPTV rebuild)

The rebuilt **Deko IPTV** app (`app.deko.iptv`, Flutter source in `../app/`, baked to
`http://iptv.sarlnsi.ovh:4500`) is hosted for sideload at:

> **http://iptv.sarlnsi.ovh:4500/deko-iptv.apk**

- Served by the FastAPI `admin` container (`GET /deko-iptv.apk` → `FileResponse`), exposed by
  the dedicated Kong route `zeniptv-apk-route` (no auth). The file lives on the host at
  `/opt/iptv-backend/downloads/deko-iptv.apk`, bind-mounted read-only into the container at
  `/app/downloads`.
- **To update the APK:** rebuild (`../app/BUILD.md`), then
  `scp app/build/app/outputs/flutter-apk/app-release.apk wowdev:/opt/iptv-backend/downloads/deko-iptv.apk`.
  No container restart needed (the file is read live per request).
- ⚠️ **Currently debug-signed** (`CN=Android Debug`). It installs via sideload, but for real
  distribution rebuild with a release keystore (see `../app/BUILD.md` → Signing). Note: switching
  signing keys later forces users to uninstall/reinstall (no in-place update across keys).

## App wiring (original `zenplayer.apk`)

The original shipped APK (`app.zeniptv.mobile`) is hardcoded to `https://api.zeniptv.app` with a
baked-in anon key, so it will **not** use this server. The Deko rebuild above is the repoint target:
same Supabase shape, new URL + anon key. See `../analysis/FEASIBILITY.md`.
