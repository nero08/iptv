# Rebuild Zen IPTV Flutter App (Code-Access Login) Implementation Plan

Created: 2026-06-01
Author: contact@sarlnsi.fr
Agent: Claude Code
Status: VERIFIED
Approved: Yes
Iterations: 0
Worktree: No
Type: Feature

## Deviations

- **Changes-review (verify phase) findings — fixed:** (must_fix) download error handler used a forced `e as DioException` cast that crashed on any non-Dio error (disk full / TLS / FS) → changed to `e is DioException && CancelToken.isCancel(e)` (`download_controller.dart`); (must_fix) `nowNextProvider` built a fresh `XtreamClient`+`EpgService` per call, discarding the EPG TTL cache and risking one HTTP request per channel per grid rebuild → hoisted a shared, source-scoped `epgServiceProvider` (`browse_providers.dart`); (must_fix) `_FavStar.onTap` called `(context as Element).markNeedsBuild()` (Flutter invariant violation) → converted to `ConsumerStatefulWidget` + `setState` (`live_screen.dart`, verified live: star now toggles, previously dead); (should_fix) added `test/download_controller_test.dart` (3 tests incl. the non-Dio regression guard); (should_fix) defensive bytes handling in `_loadM3u` (`iptv_repository.dart`). Pushed back on two should_fix items as already-safe: VOD `container_extension` (call sites already default `?? 'mp4'` and `vodStreamUrl` takes a non-null `String`), and the SQL `ACCOUNT_%` format string (the `status` CHECK constraint guarantees it yields exactly `ACCOUNT_BLOCKED`/`ACCOUNT_EXPIRED`). Suggestions (catalog autoDispose re-download, M3U credential-at-rest encryption) deferred — noted as future hardening. Final: 54/54 tests, analyze clean, release APK rebuilt + re-smoked on emulator (login restore → category → player + favorite toggle).

- **Task 19 verification surfaced a blocking bug in Task 8's `LiveChannel.fromJson`** (`app/lib/iptv/models.dart`): it never read `direct_url`, so every M3U channel rehydrated from the drift cache had `directUrl == null`. `IptvRepository.liveUrl` then fell through to the Xtream branch and dereferenced `serverUrl!` (null for M3U sources), throwing a null-check exception **inside the tap handler** — so tapping any M3U channel silently failed to open the player (the throw was swallowed by Flutter's gesture zone; in release builds only a generic `DiagnosticsProperty<void>` line is logged). This had been masked because all M3U play-path tests asserted on parsing/URL building, never on the cache→`liveUrl` round-trip. Fix: read `direct_url` in `fromJson`; added regression test `test/iptv_repository_test.dart::liveUrl resolves an M3U channel from its cached direct_url` (RED→GREEN). Full suite 51/51. Re-verified live on emulator: tapping a channel now opens the player and libmpv connects to the stream (`VideoOutput.Resize {width:768,height:576}` for the 576p source).

## Summary

**Goal:** A from-scratch, fully-owned, recompilable Flutter app (`app.zeniptv.mobile`, "Zen Player") that reproduces the original IPTV feature set (Xtream + M3U sources, Live/VOD/Series browsing, EPG, search, favorites, Netflix-style watch profiles, TMDB metadata, video playback, downloads, multi-device awareness) but logs in with an **8-character access code** validated against the already-deployed self-hosted Supabase backend (`http://iptv.sarlnsi.ovh:4500`), with per-account IPTV sources pushable from the admin backend AND user-addable in-app.

## Out of Scope

- iOS build/signing (Android APK is the deliverable; the codebase stays iOS-compatible but iOS is not built/tested here).
- OAuth / email-password / RevenueCat subscription flows — intentionally **removed**, replaced by the access-code system.
- Re-implementing the original Rust `libiptv_loader.so` — the IPTV protocol is re-implemented in pure Dart (user decision).
- Re-deploying or restructuring the backend stack — it is live; only **one additive RPC** (`get_sources_for_code`) is added (Task 2).
- Live TV catch-up / recording / Chromecast — deferred (listed in Deferred Ideas), not built.

## Context for Implementer

Two account concepts coexist and must not be conflated: (1) the **Zen account** = the 8-char code (Supabase `zeniptv.accounts`), which gates app access and carries `max_devices`; (2) the **IPTV portal account** = the user's Xtream `user_info` (per-source, lives on the user's IPTV provider, unrelated to Supabase). The app's "session" is NOT a Supabase JWT — `redeem_access_code` is an anonymous RPC returning only `{account_id, status, max_devices, device_count}`. Therefore the app persists the validated **code + a locally-generated stable device_id** in secure storage and re-validates on each launch; all backend reads that need the account go through **SECURITY DEFINER anon RPCs** keyed by `(code, device_id)`, never through RLS-protected table reads (anon is blocked by RLS on `iptv_sources`). This is why Task 2 adds `get_sources_for_code(code, device_id)` server-side.

Backend contract already live (verified, `backend/volumes/db/init/01-zeniptv-schema.sql`):
- `POST /rest/v1/rpc/redeem_access_code` body `{p_code, p_device_id, p_device_name}` → 200 `[{account_id,status,max_devices,device_count}]`; errors as PostgREST JSON with `message` in {`INVALID_CODE`, `ACCOUNT_BLOCKED`, `ACCOUNT_EXPIRED`, `DEVICE_LIMIT_REACHED`}. Header `apikey: <ANON_KEY>` required (anon key is in `backend/.env`).
- Tables `zeniptv.accounts(access_code, status, max_devices, expires_at)`, `zeniptv.iptv_sources(account_id, kind 'xtream'|'m3u', name, server_url, username, password, m3u_url, is_active)`, `zeniptv.devices(account_id, device_id, device_name, last_seen_at)`.

## Runtime Environment

- **Backend (live):** `http://iptv.sarlnsi.ovh:4500` (Supabase via Kong). Anon key: `backend/.env` -> `ANON_KEY`. Admin UI: `/admin/login`. Re-deploy backend after Task 2 via `ssh wowdev 'cd /opt/iptv-backend && ./deploy.sh'`.
- **Flutter:** local install `~/development/flutter` is **3.7.5 / Dart 2.19.2 (2023, too old)**. Task 1 upgrades it to stable >= 3.24 (Dart >= 3.5) — required by `media_kit` and `supabase_flutter` v2.
- **Emulator (verification):** AVD `Pixel_3a_API_34_extension_level_7_x86_64`, KVM available. Launch headless: `~/Android/Sdk/emulator/emulator -avd Pixel_3a_API_34_extension_level_7_x86_64 -no-window -gpu swiftshader_indirect &`. ADB at `~/Android/Sdk/platform-tools/adb`.
- **App project root:** `diskprojects/iptv/app/` (Flutter project `zen_player`, applicationId `app.zeniptv.mobile`).

## Assumptions

- A TMDB API key is available for metadata enrichment — Task 15 depends on this. If absent, TMDB enrichment degrades gracefully to Xtream-provided art (the app still works); the key is read from `--dart-define=TMDB_API_KEY=` / secure storage, never hard-coded.
- The Pixel_3a x86_64 emulator can run media_kit playback of a public test HLS/TS stream — Tasks 11/16/19 verification depends on this. If media_kit's x86_64 libs fail on the emulator, verification falls back to asserting the player widget builds + the resolved stream URL is correct (documented in that task).
- The user can supply at least one working Xtream portal OR M3U URL (or a code with backend-assigned sources) for end-to-end content verification — Tasks 9/10/19. A public IPTV test source is used otherwise and noted.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Flutter upgrade breaks/half-migrates the toolchain mid-build | Medium | High | Task 1 pins to a known stable tag, runs `flutter doctor` to green, commits `pubspec.lock`; if upgrade corrupts the shared `~/development/flutter`, fall back to an FVM-pinned SDK in the project (documented in Task 1). |
| `media_kit` native libs not present for Android x86_64 emulator | Medium | Medium | Include `media_kit_libs_android_video`; if emulator playback fails, verify on an arm64 AVD or assert URL-resolution + widget build (Assumption above). |
| Access code persisted insecurely (plaintext) -> account theft on device | Medium | High | Store code only in `flutter_secure_storage` (Keystore-backed); never in SharedPreferences/logs. Task 4 DoD asserts no plaintext code in prefs/logs. |
| Re-validate-on-launch hits `DEVICE_LIMIT_REACHED` for the legit device after reinstall (new device_id) | Medium | Medium | device_id is generated once and stored in secure storage; on `DEVICE_LIMIT_REACHED` the app shows a clear "device limit reached — manage devices in admin" screen rather than a crash (Task 5). |

## File Structure

- `app/` (create) — Flutter project `zen_player`, applicationId `app.zeniptv.mobile`, min SDK 25.
- `app/lib/main.dart` (create) — entrypoint: init secure storage, media_kit, ProviderScope, route to splash->login or home.
- `app/lib/core/config.dart` (create) — backend URL, anon key (via `--dart-define`), TMDB key, constants.
- `app/lib/core/supabase_service.dart` (create) — thin PostgREST RPC client (`redeem_access_code`, `get_sources_for_code`).
- `app/lib/core/device_id.dart` (create) — stable device_id (generate-once, secure storage) + device name via `device_info_plus`.
- `app/lib/auth/auth_controller.dart` (create) — Riverpod controller: redeem code, persist/clear session, re-validate on launch.
- `app/lib/auth/login_screen.dart` (create) — 8-char code entry UI + error mapping.
- `app/lib/auth/device_limit_screen.dart` (create) — DEVICE_LIMIT_REACHED / blocked / expired states.
- `app/lib/sources/source_models.dart` (create) — `IptvSource` (kind xtream/m3u), local + backend origin.
- `app/lib/sources/source_repository.dart` (create) — merge backend-pushed + locally-added sources; CRUD for local.
- `app/lib/sources/add_source_screen.dart` (create) — BYO add form (Xtream creds / M3U URL).
- `app/lib/iptv/xtream_client.dart` (create) — pure-Dart Xtream Codes client.
- `app/lib/iptv/m3u_parser.dart` (create) — pure-Dart M3U parser.
- `app/lib/iptv/models.dart` (create) — `LiveChannel`, `VodItem`, `SeriesItem`, `SeriesInfo`, `Season`, `Episode`, `Category`, `SourceInfo`.
- `app/lib/iptv/iptv_repository.dart` (create) — unifies Xtream + M3U behind one interface; caches catalog in drift.
- `app/lib/data/app_db.dart` (create) — drift DB: sources, catalog cache, favorites, profiles, watch history, downloads.
- `app/lib/browse/*.dart` (create) — Live/VOD/Series/Search screens + shared tiles.
- `app/lib/epg/*.dart` (create) — EPG service + now/next UI.
- `app/lib/tmdb/tmdb_service.dart` (create) — TMDB enrichment (graceful no-key fallback).
- `app/lib/profiles/*.dart`, `app/lib/favorites/*.dart` (create) — watch profiles + favorites.
- `app/lib/player/player_screen.dart` (create) — media_kit player + controls.
- `app/lib/downloads/*.dart` (create) — VOD/episode downloads + offline playback.
- `app/lib/settings/settings_screen.dart` (create) — profiles, devices, sources, logout.
- `app/test/*.dart` (create) — unit tests for xtream_client, m3u_parser, auth_controller, source merge, tmdb, epg.
- `backend/volumes/db/init/02-app-rpcs.sql` (create) — additive RPC `get_sources_for_code` + grants.

## E2E Test Scenarios

### TS-001: Login with valid code
**Priority:** Critical
**Preconditions:** A valid active code exists (create via admin API, max_devices >= 1).
**Mapped Tasks:** Task 3, 4, 5

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Launch app on emulator | Splash -> login screen with 8-char code input |
| 2 | Enter the valid code, tap "Se connecter" | App registers device, navigates to Home |
| 3 | Kill + relaunch app | Goes straight to Home (re-validated silently), no re-entry of code |

### TS-002: Invalid / blocked / expired code
**Priority:** Critical
**Preconditions:** Know one invalid string, one blocked code, one expired code.
**Mapped Tasks:** Task 4, 5

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Enter `ZZZZZZZZ`, submit | Inline error "Code invalide" (maps `INVALID_CODE`) |
| 2 | Enter a blocked code | Error "Compte bloque" (maps `ACCOUNT_BLOCKED`) |
| 3 | Enter an expired code | Error "Compte expire" (maps `ACCOUNT_EXPIRED`) |

### TS-003: Device limit
**Priority:** High
**Preconditions:** Code with `max_devices=1`, already redeemed on device A.
**Mapped Tasks:** Task 2, 5

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Clear app storage (simulate device B), enter same code | "Limite d'appareils atteinte" screen, not a crash |
| 2 | Re-open the app as device A (its stored code+device_id) | Device A still redeems successfully (no extra slot consumed; backend rejected B before inserting) |

### TS-004: Backend-pushed source appears after login
**Priority:** Critical
**Preconditions:** Admin assigns one Xtream source to the code.
**Mapped Tasks:** Task 2, 6

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Log in with that code | Source list shows the admin-assigned Xtream portal without manual entry |

### TS-005: Add own source + browse + play live
**Priority:** Critical
**Preconditions:** A working Xtream portal (or public test) URL+user+pass.
**Mapped Tasks:** Task 6, 7, 9, 11

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Open "Ajouter une source", enter Xtream creds, save | Source validated (`fetch source_infos` OK), catalog downloads |
| 2 | Open Live tab -> a category -> a channel | Channel list renders; tapping opens player |
| 3 | Player screen | Stream starts (or, per Assumption fallback, correct stream URL resolved + player widget built) |

### TS-006: VOD & Series detail
**Priority:** High
**Mapped Tasks:** Task 10, 12

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Open VOD tab -> a movie | Detail screen with artwork/overview + Play |
| 2 | Open Series tab -> a series -> a season -> an episode | Seasons/episodes render; episode opens player |

### TS-007: Favorites & Profiles
**Priority:** Medium
**Mapped Tasks:** Task 16

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Create a 2nd watch profile, switch to it | Active profile changes; favorites/history are per-profile |
| 2 | Toggle favorite on a channel, open Favorites | Channel appears; toggling off removes it |

## Progress Tracking

- [x] Task 1: Scaffold Flutter project + upgrade toolchain + dependencies
- [x] Task 2: Add backend RPC `get_sources_for_code` + redeploy
- [x] Task 3: Core services — config, PostgREST client, device_id
- [x] Task 4: Access-code auth controller + secure session persistence
- [x] Task 5: Login UI + device-limit/blocked/expired screens + launch routing
- [x] Task 6: Source models + repository (backend-pushed + BYO local) + add-source UI
- [x] Task 7: Pure-Dart Xtream Codes client
- [x] Task 8: Pure-Dart M3U parser + unified IPTV repository + drift catalog cache
- [x] Task 9: Live TV browsing (categories -> channels)
- [x] Task 10: VOD browsing + movie detail
- [x] Task 11: media_kit player screen + playback wiring
- [x] Task 12: Series browsing + season/episode detail
- [x] Task 13: EPG (short-EPG / XMLTV) now/next
- [x] Task 14: Search across cached catalog
- [x] Task 15: TMDB metadata enrichment
- [x] Task 16: Watch profiles + favorites + watch history (per profile)
- [x] Task 17: Downloads (VOD/episodes) + offline playback
- [x] Task 18: Settings + device/multi-screen awareness + logout
- [x] Task 19: Release build — signed APK + run/verify on emulator

## Implementation Tasks

### Task 1: Scaffold Flutter project + upgrade toolchain + dependencies

**Objective:** Create the `zen_player` Flutter project under `app/` with applicationId `app.zeniptv.mobile`, upgrade the local Flutter SDK to a stable channel new enough for media_kit + supabase_flutter v2, and declare all dependencies so later tasks compile. This is the foundation every other task builds on.

**Files:**

- Create: `app/` (via `flutter create`), `app/pubspec.yaml`, `app/android/app/build.gradle` (applicationId, minSdk 25), `app/lib/main.dart` (placeholder MaterialApp)
- Create: `app/.gitignore`, `app/README.md`

**Key Decisions / Notes:**

- Upgrade: `~/development/flutter` is 3.7.5; run `flutter upgrade` (or `git -C ~/development/flutter checkout <stable tag>` then `flutter doctor`). Target stable >= 3.24 / Dart >= 3.5. If the shared SDK upgrade is risky, pin via FVM inside `app/` and document the exact command in `app/README.md`.
- Dependencies (pubspec): `flutter_riverpod`, `go_router`, `dio`, `media_kit`, `media_kit_video`, `media_kit_libs_android_video`, `drift` + `sqlite3_flutter_libs`, `flutter_secure_storage`, `device_info_plus`, `cached_network_image`, `path_provider`, `permission_handler`, `uuid`, `intl`, `freezed_annotation`, `json_annotation`. Dev: `build_runner`, `drift_dev`, `freezed`, `json_serializable`, `flutter_lints`.
- applicationId `app.zeniptv.mobile`, app label "Zen Player", minSdkVersion 25, targetSdk 34.
- Add a stub `app/lib/data/app_db.dart` with an empty drift `@DriftDatabase` + part directive in this task, so codegen runs once during scaffold and later tasks (6/7) that import it compile/analyze cleanly before Task 8 fills the tables.

**Definition of Done:**

- [ ] `app/` exists; `flutter doctor` reports no blocking issues for Android; Dart >= 3.5.
- [ ] `app/android/app/build.gradle` has `applicationId "app.zeniptv.mobile"` and `minSdkVersion 25`.
- [ ] Verify: `cd app && flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter analyze` exits 0.

### Task 2: Add backend RPC `get_sources_for_code` + harden device-limit + redeploy

**Objective:** Add a SECURITY DEFINER anonymous RPC that, given `(code, device_id)`, validates the account is active and the device is registered, then returns that account's active `iptv_sources` (so the app receives admin-assigned sources after a code login — anon is RLS-blocked from reading the table directly). Also harden `redeem_access_code` to check the device cap BEFORE inserting a new device, so correctness no longer relies on transaction rollback.

**Files:**

- Create: `backend/volumes/db/init/02-app-rpcs.sql`
- Modify: `backend/deploy.sh` (apply `02-app-rpcs.sql` after `01-zeniptv-schema.sql` in step 3b)

**Key Decisions / Notes:**

- **Read `backend/deploy.sh` first** and confirm step 3b applies init SQL via `docker compose exec -T db psql -U postgres -d postgres < <file>` (idempotent — schema uses `create or replace` / `if not exists` / `on conflict do nothing`). It does NOT down/up the DB volume, so applying additive SQL on the live DB is non-destructive. If that assumption is wrong, apply `02-app-rpcs.sql` directly via `psql` instead of via a volume-resetting path.
- New RPC mirrors `redeem_access_code` (`01-zeniptv-schema.sql:131-143`): `language plpgsql security definer set search_path = public, zeniptv`, raise `INVALID_OR_INACTIVE` / `DEVICE_NOT_REGISTERED` with distinct SQLSTATEs, `grant execute ... to anon, authenticated, service_role`. Return `setof zeniptv.iptv_sources` (app reads `id,kind,name,server_url,username,password,m3u_url`). Passwords/credential-bearing `m3u_url` are returned only behind the code+device gate — acceptable for this self-hosted owner-operated model; note it in a SQL comment.
- **Device-cap hardening (in `02-app-rpcs.sql`, `create or replace` over the existing fn):** count existing devices first; if `device_id` is NOT already registered AND `cnt >= max_devices`, raise `DEVICE_LIMIT_REACHED` BEFORE any insert; only upsert (refresh `last_seen_at`) for already-registered device_ids or when under cap. This makes the already-registered device always able to re-redeem and stops a rejected new device from depending on rollback. (Note: current code is safe via transaction rollback, but this removes the implicit dependency.)
- After writing, redeploy: `ssh wowdev 'cd /opt/iptv-backend && ./deploy.sh'` (deploy.sh already restarts PostgREST to reload the schema cache).
- Test-code setup for DoD: open admin UI `http://iptv.sarlnsi.ovh:4500/admin/login` (creds = `DASHBOARD_USERNAME`/`DASHBOARD_PASSWORD` in `backend/.env`), create a test account, assign one Xtream source. Register a device by calling `redeem_access_code` once with that code + a fixed `p_device_id='test-device-001'`, THEN call `get_sources_for_code`.

**Definition of Done:**

- [ ] After `redeem_access_code` registers `test-device-001` on a code with one admin-assigned source, `POST /rest/v1/rpc/get_sources_for_code {p_code,p_device_id:'test-device-001'}` (header `apikey`) returns the source row; an unregistered device returns `DEVICE_NOT_REGISTERED`; a blocked code returns `INVALID_OR_INACTIVE`.
- [ ] Device-cap: on a `max_devices=1` code already holding device A, redeeming with device B raises `DEVICE_LIMIT_REACHED` AND no `device B` row exists afterward (`select count(*) ... where device_id='B'` = 0), AND device A can still redeem successfully (count stays 1).
- [ ] Verify: after redeploy, the two curl sequences above (anon key from `backend/.env`) return the documented JSON; plus `docker compose exec -T db psql -U postgres -d postgres -c "select count(*) from zeniptv.devices where device_id='B'"` returns 0 after the rejected B attempt.

### Task 3: Core services — config, PostgREST client, device_id

**Objective:** Provide the low-level plumbing every feature uses: a config holder (backend URL + anon key via `--dart-define`, TMDB key), a typed PostgREST client for the two RPCs, and a stable device identifier generated once and stored in secure storage.

**Files:**

- Create: `app/lib/core/config.dart`, `app/lib/core/supabase_service.dart`, `app/lib/core/device_id.dart`
- Test: `app/test/supabase_service_test.dart`

**Key Decisions / Notes:**

- `config.dart`: `const backendUrl = String.fromEnvironment('ZEN_BACKEND', defaultValue:'http://iptv.sarlnsi.ovh:4500')`, `anonKey = String.fromEnvironment('ZEN_ANON_KEY')`, `tmdbKey = String.fromEnvironment('TMDB_API_KEY', defaultValue:'')`. Pass the anon key at build via `--dart-define` to keep it out of source control. **Threat-model note (put in a code comment):** `--dart-define` is NOT a secret store — the value is embedded as a plaintext string in the compiled APK and is extractable (`strings`/`apktool`). This is acceptable here because the anon key only reaches SECURITY DEFINER RPCs gated by code+device; it does not grant table access. (Backend rate-limiting on `redeem_access_code` is a Deferred Idea.)
- `supabase_service.dart`: `dio` POST to `/rest/v1/rpc/<fn>` with headers `apikey` + `Content-Type`. Methods `redeemAccessCode(code, deviceId, deviceName)` and `getSourcesForCode(code, deviceId)`. Map PostgREST error JSON `message` -> typed `BackendException(code)`.
- `device_id.dart`: read `device_id` from `flutter_secure_storage`; if absent, generate `uuid.v4()`, store it. Device name from `device_info_plus`. Cache in-memory after first read (hot path on every RPC).

**Definition of Done:**

- [ ] `redeemAccessCode` maps a `{"message":"INVALID_CODE"}` response to `BackendException('INVALID_CODE')` (unit test with a mocked dio adapter).
- [ ] `deviceId()` returns the same value across two calls and persists across a re-read (mock secure storage).
- [ ] Verify: `cd app && flutter test test/supabase_service_test.dart`.

### Task 4: Access-code auth controller + secure session persistence

**Objective:** Implement the Riverpod auth controller that redeems a code, stores the validated code in secure storage as the session credential, exposes `AuthState` (loading/authenticated/error/deviceLimit/blocked/expired), and silently re-validates on launch.

**Files:**

- Create: `app/lib/auth/auth_controller.dart`, `app/lib/auth/auth_state.dart`
- Test: `app/test/auth_controller_test.dart`

**Key Decisions / Notes:**

- Client-side code shape validation before any network call: `^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$` — the EXACT backend `gen_access_code` alphabet (`01-zeniptv-schema.sql:15`), which excludes the look-alikes 0/O/1/I. (Do not use `[A-Z2-9]` — it wrongly accepts O and I.) On input, auto-correct typed `O`->`0`-equivalent is NOT valid here since 0 is also excluded; instead uppercase the input and reject non-alphabet chars with a friendly message.
- On success: persist `code` in `flutter_secure_storage` (key `zen_code`); set `AuthState.authenticated(accountId, maxDevices, deviceCount)`.
- On launch (`restore()`): if a stored code exists, call `redeemAccessCode` again (refreshes device `last_seen_at`); map errors to the matching `AuthState`. Distinguish network failure (keep code, show offline) from `INVALID_CODE` (clear code).
- `logout()`: clear `zen_code` (keep `device_id`).
- Map backend `message` -> state: `DEVICE_LIMIT_REACHED`->deviceLimit, `ACCOUNT_BLOCKED`->blocked, `ACCOUNT_EXPIRED`->expired, `INVALID_CODE`->error.

**Definition of Done:**

- [ ] Valid code -> state authenticated and code is written to secure storage; logout clears it but keeps device_id.
- [ ] `restore()` with a stored code that now returns `ACCOUNT_BLOCKED` yields `AuthState.blocked` and does NOT crash or wipe device_id.
- [ ] No plaintext code is written to SharedPreferences or logged (assert storage backend is secure storage only).
- [ ] Verify: `cd app && flutter test test/auth_controller_test.dart`.

### Task 5: Login UI + device-limit/blocked/expired screens + launch routing

**Objective:** Build the 8-char code login screen (the only auth UI), the terminal-state screens (device limit / blocked / expired), a splash that routes based on restored auth state, and wire navigation so an authenticated launch lands on Home.

**Files:**

- Create: `app/lib/auth/login_screen.dart`, `app/lib/auth/device_limit_screen.dart`, `app/lib/app_router.dart`, `app/lib/splash_screen.dart`
- Modify: `app/lib/main.dart` (ProviderScope + initial route = splash)

**Key Decisions / Notes:**

- Login UI: one uppercase 8-char field (auto-uppercase, monospace, char counter), "Se connecter" button, inline error text, submit disabled until 8 chars. French copy ("Entrez votre code d'acces").
- Error mapping (from `AuthState`): INVALID_CODE->"Code invalide", BLOCKED->"Compte bloque", EXPIRED->"Compte expire", deviceLimit->push `device_limit_screen` ("Limite d'appareils atteinte — gerez vos appareils depuis l'administration").
- Splash: watch `authControllerProvider`; while restoring show spinner; authenticated->Home, else->login. `restore()` runs once at splash; do not re-trigger on every rebuild.
- **Emulator prerequisite (applies to every emulator-verified task from here on — 5,9,10,11,12,13,15,16,17,18,19):** before any `adb install`, ensure the AVD is up: `~/Android/Sdk/emulator/emulator -avd Pixel_3a_API_34_extension_level_7_x86_64 -no-window -gpu swiftshader_indirect &`, then `~/Android/Sdk/platform-tools/adb wait-for-device` and poll `adb shell getprop sys.boot_completed` == 1 (up to 60s). Later emulator tasks reference this step rather than repeating it.

**Definition of Done:**

- [ ] TS-001 (valid login -> Home; relaunch -> straight to Home) passes on the emulator.
- [ ] TS-002 (invalid/blocked/expired inline errors) and TS-003 (device-limit screen, no crash) pass on the emulator.
- [ ] Verify: build+install+drive on emulator (screenshots saved under `app/verification/`), plus `flutter analyze` clean.

### Task 6: Source models + repository (backend-pushed + BYO local) + add-source UI

**Objective:** Model an IPTV source (Xtream or M3U), and a repository that merges admin-assigned sources from `get_sources_for_code` with user-added local sources persisted in drift, plus the "Ajouter une source" form for BYO entry with validation.

**Files:**

- Create: `app/lib/sources/source_models.dart`, `app/lib/sources/source_repository.dart`, `app/lib/sources/add_source_screen.dart`, `app/lib/sources/source_list_screen.dart`
- Modify: `app/lib/data/app_db.dart` (LocalSources table — defined in Task 8's DB, used here)
- Test: `app/test/source_repository_test.dart`

**Key Decisions / Notes:**

- `IptvSource{id, origin: backend|local, kind: xtream|m3u, name, serverUrl?, username?, password?, m3uUrl?}`. Backend sources are read-only in-app; local sources are CRUD.
- Repository `allSources()` = backend (`getSourcesForCode`) + local (drift), deduped by (kind, serverUrl|m3uUrl, username). Backend wins on conflict.
- Add-source form validates by calling Task 7's `fetchSourceInfo` (Xtream) before saving; M3U validates by a successful download/parse of the first lines.
- `activeSourceProvider` persists the selected source id — mirrors original `active_source_id`.
- M3U URLs may embed credentials (`?username=&password=`). Use an obscured (password-style) text field for the M3U URL input, and in the source list show only the host portion, never the raw credential-bearing URL.

**Definition of Done:**

- [ ] `allSources()` returns backend + local with backend-wins dedup (unit test with fake backend + in-memory drift).
- [ ] TS-004 (admin-assigned source appears after login, no manual entry) passes on emulator.
- [ ] Adding an invalid Xtream source shows a validation error and does not persist.
- [ ] Verify: `cd app && flutter test test/source_repository_test.dart` + emulator check for TS-004.

### Task 7: Pure-Dart Xtream Codes client

**Objective:** Implement the Xtream Codes protocol in pure Dart: authenticate/read `user_info`+`server_info`, list categories and streams for live/VOD/series, fetch VOD and series detail, and build playable stream URLs — replacing the original Rust client.

**Files:**

- Create: `app/lib/iptv/xtream_client.dart`, `app/lib/iptv/models.dart`
- Test: `app/test/xtream_client_test.dart`

**Key Decisions / Notes:**

- Base: `GET {server}/player_api.php?username=&password=&action=<a>`. Actions: `get_live_categories`, `get_live_streams`, `get_vod_categories`, `get_vod_streams`, `get_series_categories`, `get_series`, `get_vod_info`, `get_series_info`, `get_short_epg`. No-action call -> `{user_info, server_info}` (validation).
- Stream URL builders: live `{server}/live/{user}/{pass}/{stream_id}.{ext}` (ext default `ts`), VOD `{server}/movie/{user}/{pass}/{stream_id}.{container_extension}`, series episode `{server}/series/{user}/{pass}/{episode_id}.{container_extension}`.
- Models in `models.dart`: `SourceInfo`, `Category`, `LiveChannel`, `VodItem`, `SeriesItem`, `SeriesInfo`(seasons), `Episode`, `EpgEntry` — JSON-mapped from Xtream snake_case (mirror original `RawXtreamMovie/Serie/Channel/Category`, `XtreamSeason`, `XtreamVodInfo`, `XtreamSerieInfo`).
- Use `dio`; tolerate Xtream quirks (numbers-as-strings, empty arrays) via `_asInt`/`_asString` helpers. Parsing must stream large lists without N^2 work (catalog hot path).

**Definition of Done:**

- [ ] Given recorded Xtream JSON fixtures, the client parses categories/live/VOD/series and builds the three stream-URL forms correctly (unit tests with fixtures under `app/test/fixtures/xtream/`).
- [ ] `_asInt`/`_asString` handle string-encoded numbers and nulls without throwing.
- [ ] Verify: `cd app && flutter test test/xtream_client_test.dart`.

### Task 8: Pure-Dart M3U parser + unified IPTV repository + drift catalog cache

**Objective:** Implement an M3U/M3U8 playlist parser, define the drift database (sources, catalog cache, favorites, profiles, history, downloads), and a unified `IptvRepository` presenting Xtream and M3U sources behind one interface with a drift-backed catalog cache.

**Files:**

- Create: `app/lib/iptv/m3u_parser.dart`, `app/lib/iptv/iptv_repository.dart`, `app/lib/data/app_db.dart`
- Test: `app/test/m3u_parser_test.dart`

**Key Decisions / Notes:**

- M3U parser: `#EXTM3U`, `#EXTINF:-1 tvg-id="" tvg-logo="" group-title="",<name>` + URL line -> `LiveChannel`(name, logo, group, url). Group-title becomes the category. Tolerate missing attrs (small regex). Decode the downloaded body defensively: try UTF-8, fall back to `latin1` for non-UTF-8 portals (`dio` with `responseType: bytes` + manual decode) rather than letting a decode error abort the whole playlist.
- drift `app_db.dart` tables: `LocalSources`, `CatalogChannels`/`CatalogVod`/`CatalogSeries` (cache, keyed by sourceId+type), `Favorites(profileId, itemKey)`, `Profiles`, `WatchHistory(profileId, itemKey, position)`, `Downloads`. Consumed across Tasks 6,9,10,12,14,16,17.
- `IptvRepository.loadCatalog(source)` -> for Xtream call client actions; for M3U download+parse; persist to drift cache; expose category/list/detail reads from cache for fast browsing. UI reads from cache; network refresh is explicit (pull-to-refresh) to avoid re-downloading per screen.

**Definition of Done:**

- [ ] M3U parser turns a sample playlist (with tvg attrs + groups) into the correct `LiveChannel` list including group->category (unit test).
- [ ] drift schema compiles via `build_runner` and an in-memory DB round-trips a source + cached channels.
- [ ] Verify: `cd app && dart run build_runner build --delete-conflicting-outputs && flutter test test/m3u_parser_test.dart`.

### Task 9: Live TV browsing (categories -> channels)

**Objective:** Build the Live tab: list live categories, drill into a category to a channel grid/list (with logos), and open a channel in the player. Reads from the drift catalog cache populated by the repository.

**Files:**

- Create: `app/lib/browse/live_screen.dart`, `app/lib/browse/category_list.dart`, `app/lib/browse/media_tile.dart`, `app/lib/browse/browse_providers.dart`, `app/lib/browse/home_shell.dart`
- Modify: `app/lib/app_router.dart` (Live route + home shell tabs)

**Key Decisions / Notes:**

- Riverpod providers: `liveCategoriesProvider(sourceId)`, `liveChannelsProvider(categoryId)` reading drift cache; pull-to-refresh triggers `IptvRepository.loadCatalog`.
- `media_tile.dart` (generic, reused by VOD/Series) uses `cached_network_image` for logos/posters with a placeholder; tapping a live channel pushes the player with the resolved stream URL (Task 7 builder).
- `home_shell.dart` is the bottom-nav shell (Live/VOD/Series/Search/Settings); VOD/Series/Search tabs fill in later tasks.
- Lists use `ListView.builder`/`GridView.builder` (lazy); no full-catalog in-memory materialization.

**Definition of Done:**

- [ ] TS-005 steps 1-2 (Xtream source -> Live category -> channel list renders with logos) pass on emulator.
- [ ] Pull-to-refresh re-fetches and updates the channel list.
- [ ] Verify: emulator drive of Live browsing (screenshots in `app/verification/`), `flutter analyze` clean.

### Task 10: VOD browsing + movie detail

**Objective:** Build the VOD tab mirroring Live (categories -> movie grid), plus a movie detail screen showing metadata and a Play action that opens the VOD stream in the player.

**Files:**

- Create: `app/lib/browse/vod_screen.dart`, `app/lib/browse/vod_detail_screen.dart`
- Modify: `app/lib/app_router.dart` (VOD routes), `app/lib/browse/browse_providers.dart` (VOD providers)

**Key Decisions / Notes:**

- `vodCategoriesProvider`, `vodListProvider(categoryId)` from cache; detail uses Xtream `get_vod_info` (cached) for plot/genre/duration/poster.
- Detail screen: poster (`cached_network_image`), title, year, genre, plot, Play button -> player with VOD stream URL. TMDB enrichment (Task 15) overlays artwork when available.
- Reuse the generic `media_tile` grid from Task 9 — do not duplicate tile logic.

**Definition of Done:**

- [ ] TS-006 step 1 (VOD -> movie -> detail with artwork/overview, Play present) passes on emulator (artwork may be Xtream `stream_icon` if TMDB key absent).
- [ ] Verify: emulator drive of VOD browse+detail (screenshots), `flutter analyze` clean.

### Task 11: media_kit player screen + playback wiring

**Objective:** Implement the universal playback screen with media_kit: play any resolved stream URL (live TS/HLS, VOD/series MP4/MKV), with standard controls (play/pause, seek for VOD, fullscreen, audio/subtitle tracks where present) and a back-safe lifecycle.

**Files:**

- Create: `app/lib/player/player_screen.dart`, `app/lib/player/player_controls.dart`
- Modify: `app/lib/main.dart` (`MediaKit.ensureInitialized()`)

**Key Decisions / Notes:**

- Use `media_kit` `Player` + `media_kit_video` `Video` widget. Live = no seek bar; VOD/series = seek + resume position (from `WatchHistory`, Task 16).
- Pass stream URL + display title + isLive flag. Dispose the player on pop to free native resources (hot path — leaks crash on repeated opens).
- Track selection (audio/subtitle) exposed when the media reports multiple tracks.
- Per Assumption: if emulator x86_64 playback fails, the task still verifies the player builds and receives the correct URL; document the fallback in code comments + verification notes.

**Definition of Done:**

- [ ] TS-005 step 3 (player starts the live stream) passes on emulator, OR the documented fallback (correct URL + widget builds) is recorded with the reason.
- [ ] Opening and closing the player 5x does not leak/crash (player disposed each time).
- [ ] Verify: emulator playback attempt (screenshot/log in `app/verification/`), `flutter analyze` clean.

### Task 12: Series browsing + season/episode detail

**Objective:** Build the Series tab (categories -> series grid -> series detail with seasons and episodes), opening an episode in the player.

**Files:**

- Create: `app/lib/browse/series_screen.dart`, `app/lib/browse/series_detail_screen.dart`
- Modify: `app/lib/app_router.dart`, `app/lib/browse/browse_providers.dart`

**Key Decisions / Notes:**

- `seriesCategoriesProvider`, `seriesListProvider(categoryId)` from cache; detail uses Xtream `get_series_info` -> `SeriesInfo{seasons:[{episodes:[...]}]}` (Task 7 models).
- Detail UI: series poster/plot, season selector (tabs or dropdown), episode list; tapping an episode builds the series stream URL and opens the player.
- Reuse the generic `media_tile` grid + the player launch path from Tasks 9/11.

**Definition of Done:**

- [ ] TS-006 step 2 (Series -> series -> season -> episode -> player) passes on emulator.
- [ ] Season switching updates the episode list correctly.
- [ ] Verify: emulator drive of Series browse+detail (screenshots), `flutter analyze` clean.

### Task 13: EPG (short-EPG / XMLTV) now/next

**Objective:** Add EPG support for live channels: fetch per-channel short EPG via Xtream `get_short_epg` (base64 titles) and show now/next program info on channel tiles and as a player overlay.

**Files:**

- Create: `app/lib/epg/epg_service.dart`, `app/lib/epg/epg_models.dart`
- Modify: `app/lib/browse/media_tile.dart` (now/next line for live), `app/lib/player/player_screen.dart` (EPG-now overlay for live)
- Test: `app/test/epg_service_test.dart`

**Key Decisions / Notes:**

- Primary: Xtream `get_short_epg&stream_id=` -> entries with base64-encoded `title`/`description`, `start`/`end` epoch. Decode base64, parse times with `intl`.
- Optional XMLTV (`xmltv.php`) parse guarded by size; skip if too large on first pass — log the cap, do not silently drop.
- `epgService.nowNext(channelId)` cached briefly (EPG changes slowly) to avoid refetch on every tile build (hot path).

**Definition of Done:**

- [ ] `get_short_epg` base64 payload parses to now/next entries with correct titles+times (fixture unit test).
- [ ] For an EPG-capable source on emulator, a channel tile shows the current program and the player overlay shows now/next (or, if the test source lacks EPG, record that and rely on the fixture test).
- [ ] Verify: `cd app && flutter test test/epg_service_test.dart` + emulator check when EPG source available.

### Task 14: Search across cached catalog

**Objective:** Implement a Search tab that queries the cached catalog (live + VOD + series) by title and returns grouped results, each opening the right detail/player.

**Files:**

- Create: `app/lib/browse/search_screen.dart`, `app/lib/browse/search_providers.dart`
- Modify: `app/lib/data/app_db.dart` (search query over cache; optional FTS)

**Key Decisions / Notes:**

- Search the drift catalog cache (case/diacritics-insensitive `LIKE`, or drift FTS5 mirroring original `channels_fts`/`movies_fts`/`series_fts`). Debounce input (~300 ms) to avoid querying per keystroke (hot path).
- Results grouped by type (Live/VOD/Series); tapping routes to the existing detail/player. No network calls — pure cache query.

**Definition of Done:**

- [ ] Typing a known title returns it under the correct group and tapping opens the right screen (emulator).
- [ ] Debounce verified: rapid typing does not fire a query per character (unit test on the debounced provider).
- [ ] Verify: `cd app && flutter test test/search_test.dart` + emulator search drive (screenshot).

### Task 15: TMDB metadata enrichment

**Objective:** Enrich VOD and series detail with TMDB artwork/overview when a TMDB API key is configured, keyed by the `tmdb_id` Xtream provides (or a title+year search fallback), degrading gracefully to Xtream-provided art when no key is present.

**Files:**

- Create: `app/lib/tmdb/tmdb_service.dart`, `app/lib/tmdb/tmdb_models.dart`
- Modify: `app/lib/browse/vod_detail_screen.dart`, `app/lib/browse/series_detail_screen.dart`
- Test: `app/test/tmdb_service_test.dart`

**Key Decisions / Notes:**

- `https://api.themoviedb.org/3/{movie|tv}/{tmdb_id}?api_key=` ; images `https://image.tmdb.org/t/p/w500{path}`. If `tmdb_id` missing, `search/{movie|tv}?query=&year=` fallback.
- If `config.tmdbKey` empty -> skip TMDB entirely, use Xtream `stream_icon`/`cover` (no error, no broken UI).
- Cache TMDB responses (drift or memory LRU) keyed by tmdb_id to avoid refetch on every detail open (hot path; respect TMDB rate limits).

**Definition of Done:**

- [ ] TMDB response parses to poster+overview; the no-key path returns Xtream art and raises no error (unit tests for both).
- [ ] With a TMDB key set, a VOD detail shows TMDB poster+overview on emulator; with no key, it shows Xtream art and no error.
- [ ] Verify: `cd app && flutter test test/tmdb_service_test.dart` + one emulator detail check with a key.

### Task 16: Watch profiles + favorites + watch history (per profile)

**Objective:** Implement Netflix-style watch profiles (create/edit/delete, switch active), per-profile favorites (toggle + list), and per-profile resume/watch history used by the player.

**Files:**

- Create: `app/lib/profiles/profile_controller.dart`, `app/lib/profiles/profiles_screen.dart`, `app/lib/favorites/favorites_controller.dart`, `app/lib/favorites/favorites_screen.dart`
- Modify: `app/lib/player/player_screen.dart` (write/read resume position), `app/lib/browse/media_tile.dart` (favorite toggle), `app/lib/data/app_db.dart` (Profiles/Favorites/WatchHistory CRUD)
- Test: `app/test/favorites_profiles_test.dart`

**Key Decisions / Notes:**

- `activeProfileProvider` (persisted) selects the profile; favorites and history keyed by `profileId` (mirrors original `preferred_watch_profile_id`, per-profile histories).
- Favorite toggle on any channel/VOD/series tile; Favorites screen lists the current profile's favorites grouped by type.
- Player writes `WatchHistory(position)` on pause/exit for VOD/series; on reopen offer "Reprendre". At least one default profile auto-created on first run.

**Definition of Done:**

- [ ] TS-007 (create 2nd profile, switch, per-profile favorites; toggle on/off reflects in Favorites) passes on emulator.
- [ ] Resume: closing a VOD mid-playback and reopening offers resume at the saved position.
- [ ] Verify: `cd app && flutter test test/favorites_profiles_test.dart` + emulator TS-007.

### Task 17: Downloads (VOD/episodes) + offline playback

**Objective:** Allow downloading VOD movies and series episodes to local storage via `dio` with progress, list/manage downloads, and play downloaded files offline through the same player.

**Files:**

- Create: `app/lib/downloads/download_controller.dart`, `app/lib/downloads/downloads_screen.dart`
- Modify: `app/lib/browse/vod_detail_screen.dart`, `app/lib/browse/series_detail_screen.dart` (Download action), `app/lib/data/app_db.dart` (Downloads table), `app/lib/player/player_screen.dart` (play local file path)

**Key Decisions / Notes:**

- `dio.download(streamUrl, filePath, onReceiveProgress:)` to `getApplicationDocumentsDirectory()` (app-internal — **no storage permission required on Android API 33/34**, the emulator target). Persist `Downloads{itemKey, title, path, bytes, status}` in drift.
- Do NOT use external/public Downloads dir (would require `READ_MEDIA_VIDEO` + runtime request on API 33+). If a future change moves to a user-visible folder, declare `READ_MEDIA_VIDEO` in `AndroidManifest.xml` and request it via `permission_handler` (already in pubspec).
- Downloads screen: progress bars, cancel/delete, tap completed -> player with local file URI. Live streams are not downloadable (hide the action for live).
- Guard storage: show size, allow delete; stream to disk (do not buffer whole file in memory / block UI).

**Definition of Done:**

- [ ] Downloading a small VOD shows progress, completes, appears in Downloads, and plays from local file offline (emulator; small test clip) — with NO storage-permission prompt or error on API 34 (app-internal dir).
- [ ] Cancel/delete removes the partial/complete file and the drift row.
- [ ] Verify: emulator download+offline-play drive (screenshots/log) + `flutter analyze` clean.

### Task 18: Settings + device/multi-screen awareness + logout

**Objective:** Build the Settings tab: manage profiles, manage sources, show this device + the account's device usage (count vs max), a multi-screen awareness note, TMDB key entry, and logout (clears the code, keeps device_id).

**Files:**

- Create: `app/lib/settings/settings_screen.dart`, `app/lib/settings/devices_section.dart`
- Modify: `app/lib/app_router.dart` (Settings route), `app/lib/auth/auth_controller.dart` (expose maxDevices/deviceCount for display)

**Key Decisions / Notes:**

- Device info: show current device name + `device_count/max_devices` (from the last `redeem` response). Device removal is admin-side — the app links to "gerez vos appareils depuis l'administration"; it does not delete others' devices.
- Multi-screen awareness: surface the device-cap reality and active-connection note (mirrors original "watching on another device"). No enforcement beyond the backend cap.
- TMDB key field writes to secure storage, overrides the `--dart-define` default at runtime.
- Logout -> clears `zen_code`, routes to login; device_id preserved so re-login does not consume a new device slot.

**Definition of Done:**

- [ ] Settings shows device usage (`n/max`), profile + source management entry points, and logout returns to login while preserving device_id (re-login does not increment device count).
- [ ] Verify: emulator drive (screenshots) + `flutter analyze` clean.

### Task 19: Release build — signed APK + run/verify on emulator

**Objective:** Produce a release-configurable signed APK, confirm it installs and runs the full login->source->browse->play flow on the emulator, and document the build/run commands for Android Studio recompilation.

**Files:**

- Create: `app/android/key.properties.example`, `app/BUILD.md` (build + `--dart-define` + keystore instructions)
- Modify: `app/android/app/build.gradle` (release signingConfig referencing `key.properties` when present, else debug)

**Key Decisions / Notes:**

- Build: `flutter build apk --release --dart-define=ZEN_ANON_KEY=<anon> --dart-define=TMDB_API_KEY=<key>`. Document that the anon key comes from `backend/.env`.
- Keystore: provide `key.properties.example` + `keytool` command in `BUILD.md`; if no keystore present, fall back to debug signing so the APK installs (note this clearly).
- Final acceptance run on emulator end-to-end with a real/test code + source.

**Definition of Done:**

- [ ] `flutter build apk --release --dart-define=...` produces `app/build/app/outputs/flutter-apk/app-release.apk`.
- [ ] The built APK installs on the emulator and completes login (valid code) -> add/receive source -> browse -> open player, captured in `app/verification/`.
- [ ] Verify: `cd app && flutter build apk --release --dart-define=ZEN_ANON_KEY=$ANON` then `adb install -r build/app/outputs/flutter-apk/app-release.apk` and a scripted emulator drive.

## E2E Results

Verified on the **release APK** (debug-signed fallback, no keystore), AVD `Pixel_3a_API_34`, against the live backend `http://iptv.sarlnsi.ovh:4500` with test code `<test-access-code>` (backend M3U source). Artifacts in `app/verification/` (`TASK19-release-e2e.md` + screenshots).

| Scenario | Priority | Result | Notes |
|----------|----------|--------|-------|
| TS-001 login + relaunch restore | Critical | PASS | valid code → home; kill+relaunch → straight to home (secure-storage restore) |
| TS-004 backend source received | Critical | PASS | M3U source pushed via `get_sources_for_code`, catalog auto-loaded |
| TS-005 add/receive → browse → play | Critical | PASS | category → channel grid (logos) → player opens; libmpv `VideoOutput.Resize 768×576` (video surface black under emulator S/W rendering — env limitation, not app) |
| Search → result → player | Critical | PASS | "news" → 50 ListTile results |
| TS-007 favorites toggle | Medium | PASS | per-tile star toggles (post-fix), per-profile |
| VOD / Series / EPG detail | High | UNIT_VERIFIED | test code's source is M3U (no Xtream VOD/Series/EPG); logic covered by fixture unit tests — documented Assumption |
| Downloads | High | UNIT_VERIFIED | needs an Xtream VOD; `download_controller_test.dart` covers happy/cancel/error lifecycle |

**Live-target probe:** Tier 1/2 (no local web server — this is a mobile app, not a web service); the live target is the Android emulator running the installed APK against the live backend (reached directly). E2E executed against that running instance via adb/uiautomator.

## Goal Verification

### Truths

1. A user who enters a valid 8-char code on a fresh install reaches a working IPTV browsing experience (Live/VOD/Series) sourced from either an admin-assigned source or one they added, and can open a stream in the player — with no email/password/OAuth/subscription anywhere in the flow.
2. The same account's device limit is enforced end-to-end: redeeming beyond `max_devices` shows the device-limit screen (no crash), and logout->re-login on the same device does not consume an extra device slot.
3. The app is rebuildable into an installable APK from source with only a backend anon key (and optional TMDB key) supplied at build time — no dependency on the original app's binaries.

## Deferred Ideas

- Catch-up TV / recording, Chromecast/AirPlay, picture-in-picture.
- iOS build + App Store packaging.
- Replacing local catalog cache sync with Supabase Realtime push when the admin changes a source.
- Rate-limiting `redeem_access_code` at the backend (Kong rate-limit plugin or PostgREST pre-request) to blunt brute-force of 8-char codes if the anon key is extracted from a distributed APK.
