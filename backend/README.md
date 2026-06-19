# Deko IPTV — self-hosted backend (Supabase + admin)

Self-hosted Supabase (so the Deko IPTV app can eventually talk to it) plus a
custom FastAPI admin for **8-char access-code accounts** and **per-account IPTV
sources**. Deployed on `51.75.77.132`, exposed on **`http://iptv.sarlnsi.ovh:4500`**.

## Public surface (single port 4500, via Kong gateway)

| Path | Service | Purpose |
|------|---------|---------|
| `/auth/v1/*`  | GoTrue    | app login (Supabase auth) |
| `/rest/v1/*`  | PostgREST | data API (`zeniptv` schema + standard) |
| `/admin`, `/admin/*` | FastAPI | **account/IPTV management UI + JSON API** |
| `/` | Studio | generic DB admin UI (basic-auth) |

Postgres is **not** published publicly (only `127.0.0.1:5433` on the host for
SSH-tunnel admin).

## Domain model (`zeniptv` schema)

- `accounts` — one row = one **8-char uppercase code** (`gen_access_code()`),
  `status` (active/blocked/expired), `max_devices`, `expires_at`.
- `iptv_sources` — per-account Xtream portals or M3U playlists.
- `devices` — registered devices, enforces `max_devices`.
- `redeem_access_code(code, device_id, name)` — the app calls this at login;
  validates code + status + expiry + device cap, registers the device.

## Operate

```bash
cd /opt/iptv-backend
./deploy.sh                       # build + start + apply schema + health probe
docker compose ps                 # status
docker compose logs -f admin      # logs
docker compose down               # stop (keeps data volume)
```

Credentials are in `.env` / `CREDENTIALS.txt` (server-only). Admin UI + Studio
login: `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`.

## Admin JSON API (scripting)

```bash
TOKEN=<ADMIN_API_TOKEN from .env>
BASE=http://iptv.sarlnsi.ovh:4500/admin/api
curl -H "Authorization: Bearer $TOKEN" $BASE/accounts                       # list
curl -H "Authorization: Bearer $TOKEN" -d '{"label":"Jean","max_devices":2}' $BASE/accounts   # create
```

## App wiring (later, needs Flutter source)

The shipped APK is hardcoded to `https://api.zeniptv.app` with a baked-in anon
key, so it will **not** use this server until repointed — which requires the
Flutter source (clean) or a binary patch. This stack is the target for that
repoint: same Supabase shape (`/auth/v1`, `/rest/v1`), new URL + anon key.
See `../analysis/FEASIBILITY.md`.
