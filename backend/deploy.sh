#!/usr/bin/env bash
# Deploy / update the Deko IPTV backend stack on the server.
# Idempotent: safe to re-run. Run from /opt/iptv-backend on the server.
set -euo pipefail
cd "$(dirname "$0")"

PW=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2-)
ANON=$(grep '^ANON_KEY=' .env | cut -d= -f2-)

echo "==> 0. Render Kong declarative config from template + .env"
set -a; . ./.env; set +a
SUPABASE_ANON_KEY="$ANON_KEY" SUPABASE_SERVICE_KEY="$SERVICE_ROLE_KEY" \
  envsubst '$SUPABASE_ANON_KEY $SUPABASE_SERVICE_KEY $DASHBOARD_USERNAME $DASHBOARD_PASSWORD' \
  < volumes/api/kong.yml > volumes/api/kong.generated.yml
echo "   kong config rendered ($(grep -cE '^\s+- name:' volumes/api/kong.generated.yml) services)"

echo "==> 1. Pull images + build admin"
docker compose pull --quiet db auth rest meta studio kong || true
docker compose build admin

echo "==> 2. Start db first, wait for health"
docker compose up -d db
for i in $(seq 1 60); do
  st=$(docker inspect -f '{{.State.Health.Status}}' zeniptv-db-1 2>/dev/null || echo starting)
  [ "$st" = "healthy" ] && { echo "   db healthy"; break; }
  sleep 2
done

echo "==> 3a. Align service role passwords with .env (idempotent)"
# The supabase/postgres image may set these differently; force-align the roles
# our services authenticate as. PW is alphanumeric-only (safe to embed).
docker compose exec -T db psql -U postgres -d postgres <<SQL
ALTER ROLE supabase_admin       WITH PASSWORD '${PW}';
ALTER ROLE authenticator        WITH PASSWORD '${PW}';
ALTER ROLE supabase_auth_admin  WITH PASSWORD '${PW}';
ALTER ROLE supabase_storage_admin WITH PASSWORD '${PW}';
SQL

echo "==> 3b. Apply zeniptv schema (idempotent, as postgres superuser over socket)"
docker compose exec -T db psql -U postgres -d postgres \
  < volumes/db/init/01-zeniptv-schema.sql

echo "==> 3b-2. Apply app RPCs (get_sources_for_code + hardened redeem)"
docker compose exec -T db psql -U postgres -d postgres \
  < volumes/db/init/02-app-rpcs.sql

echo "==> 3c. Reload PostgREST schema cache (pick up zeniptv + rpc)"
docker compose restart rest >/dev/null 2>&1 || true

echo "==> 4. Start the rest of the stack"
docker compose up -d

echo "==> 5. Status"
docker compose ps

echo "==> 6. Local health probes (inside server)"
sleep 10
printf "   auth/v1/health : "; curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:4500/auth/v1/health" || true
printf "   admin/healthz  : "; curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:4500/admin/healthz" || true
printf "   rest (anon)    : "; curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:4500/rest/v1/" -H "apikey: $ANON" || true
echo "==> done."
