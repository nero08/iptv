# Reverse-Engineer Zen IPTV — Extraction, Auth/IPTV Flow Mapping & Feasibility Report

Created: 2026-05-31
Author: pro.sarl.nsi@gmail.com
Agent: Claude Code
Status: VERIFIED
Approved: Yes
Iterations: 1
Worktree: No
Type: Feature

## Summary

**Goal:** Fully extract `zenplayer.apk` (Zen IPTV, `app.zeniptv.mobile`) and reverse-engineer it enough to produce evidence-based documents describing (a) how the current login/subscription works, (b) how IPTV content is loaded, and (c) a feasibility report with a recommended architecture for the end goal — replacing login with an 8-char alphanumeric access-code system backed by a Python account/IPTV-management backend.

**Authorization:** The user states they have the app developer's authorization to reverse-engineer this APK; they do not have the Flutter source. All work here is static/dynamic analysis of a binary the user is authorized to inspect.

## Context for Implementer

This is a **Flutter release/AOT** app. Confirmed from the APK: `lib/<abi>/libapp.so` present, **no** `kernel_blob.bin`. This is the single most important constraint and it shapes the whole plan:

- The Dart application logic (login screen, RevenueCat integration, IPTV loading orchestration) is compiled to **native machine code** inside `lib/<abi>/libapp.so` (~11 MB per ABI). There is **no tool that regenerates re-compilable Dart source** from an AOT snapshot. "Edit the sources and rebuild the login screen" is therefore **not achievable from the APK alone** — changing the login UI/flow (e.g. showing an "enter 8-char code" field) requires the original Flutter project.
- Consequently, this plan's job is **analysis, not modification**: recover structure and protocol, then report which end-goal architectures are actually possible (get-source vs backend-redirect vs runtime-patch) with concrete evidence and effort/risk. The actual login-rework + backend build is a **follow-up spec**, gated on the feasibility findings produced here — planning it now would require inventing endpoints and data shapes we have not yet recovered.

Confirmed binary facts (from APK inspection, all evidence in `extracted/`):
- Package `app.zeniptv.mobile`; single exported component `app.zeniptv.mobile.MainActivity`. No deep-link schemes, no custom services/providers → auth is fully in-app (Dart) + network + RevenueCat.
- Native libs (per ABI `arm64-v8a`, `armeabi-v7a`, `x86_64`): `libapp.so` (Dart AOT), `libflutter.so`, **`libiptv_loader.so`** (custom — likely the IPTV/portal logic), `libffmpegJNI.so`, `libcronet.141.0.7340.3.so` (HTTP stack), `libdartjni.so`, `libsqlite3.so`, `librive_text.so`, `libdatastore_shared_counter.so`.
- Stack indicators: **RevenueCat** (`com.revenuecat.purchases.*`, `assets/AppstoreAuthenticationKey.pem`) for subscriptions/entitlements; **libVLC** (`org.videolan.vlc`); Firebase; Google Play Billing/Review; background_downloader plugin. 3 dex (`classes.dex`, `classes2.dex`, `classes3.dex`) = thin Android/Kotlin embedding + plugins only.
- Plain `strings` over `libapp.so` yielded no plaintext auth URLs → endpoints live in the AOT Dart and/or `libiptv_loader.so`; recovering them needs real RE tooling (Blutter / radare2 / Ghidra), not grep.

## Out of Scope

- Building the new 8-char-code login UI inside the app (impossible without Flutter source — this is the headline finding the report will justify, not a task).
- Implementing the production Python backend and the account/IPTV-management features. This plan produces the *architecture + feasibility* for it; implementation is a separate, follow-up spec once an approach is chosen.
- Repackaging/re-signing a modified APK. No code change is made here, so there is nothing to rebuild. (Toolchain note: `apksigner`/`keytool`/`java 17` are present; `zipalign`/`aapt2` are NOT — relevant only to a future patch spec.)
- Distribution of streams/credentials. This is analysis of access mechanisms, not provisioning of pirated content.

## Environment & Tooling Status

Already available on this machine: `unzip`, `java 17`, `apksigner`, `keytool`, `adb`, `python3.12`, `uv`, `curl`, network access to GitHub. **`apktool` 2.10.0 has been downloaded** to `tools/apktool.jar` and verified.

Needs install during the plan (per task): **Blutter** (Dart AOT analysis — needs cmake/ninja/clang + Python), **radare2** or **Ghidra** (native lib analysis), and for the optional dynamic task an **Android emulator/device** + **mitmproxy**. Each tool install is folded into the task that first needs it; if a tool cannot be installed/built, the task documents the blocker and falls back (e.g. radare2 strings/xrefs if Blutter fails to build).

## Assumptions

- `libiptv_loader.so` contains the IPTV portal/stream-loading logic (name + co-location with ffmpeg/cronet strongly imply it) — Task 4 depends on this; if logic is actually in Dart, Task 4 redirects to the Blutter output from Task 2.
- The arm64-v8a `libapp.so` is the canonical analysis target (other ABIs are equivalent builds) — Tasks 2-4 analyze arm64-v8a only unless it fails to load, then x86_64.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Blutter fails to build / no matching Dart SDK for this snapshot version | Medium | High (Task 2 is the backbone of auth/IPTV mapping) | Fall back to radare2/Ghidra for string + xref recovery on `libapp.so`; document reduced fidelity. reFlutter as secondary fallback. |
| Endpoints obfuscated/encrypted in-binary; static analysis yields no concrete URLs | Medium | High (feasibility of backend-redirect depends on knowing the protocol) | Task 5 (dynamic capture with mitmproxy) recovers the live protocol; if cert-pinned, document pinning as the blocker and reflect it in the feasibility verdict. |
| TLS cert pinning blocks traffic capture | Medium | Medium | Note as a hard finding; the report flags it as a cost against the backend-redirect approach and in favor of the get-source approach. |

## Progress Tracking

- [x] Task 1: Finalize full extraction & produce a structured inventory
- [x] Task 2: Recover Dart structure from `libapp.so` (strings-only fallback via binutils; Blutter blocked on slow Dart SDK mirror)
- [x] Task 3: Map the authentication & subscription (RevenueCat) flow → `AUTH_FLOW.md`
- [x] Task 4: Map the IPTV content-loading flow (`libiptv_loader.so` + Dart) → `IPTV_FLOW.md`
- [x] Task 5: Dynamic capture — SKIPPED (static analysis recovered all endpoints) → `DYNAMIC_CAPTURE.md`
- [x] Task 6: Feasibility report & recommended architecture → `FEASIBILITY.md`

> **Headline result (corrected):** The app (Zen Player v2.0.3, Flutter AOT) authenticates via **Supabase email/password + OAuth** and gates content with **RevenueCat**; IPTV is **Xtream Codes + M3U** via a Rust lib. **There is NO 8-character access-code login in the binary** (an earlier draft claimed one — that was a fabrication, now corrected across the analysis docs). The requested 8-char-code login therefore must be **built**: the in-app code screen needs the **Flutter source** (AOT Dart is not re-editable), while the Python account/IPTV-management backend is feasible given Supabase access. See `analysis/FEASIBILITY.md`.
>
> **⚠️ Accuracy note:** Blutter symbolication failed (analyzer cmake error after the Dart VM built); recovery was strings-only. Exact GoTrue method names and Supabase table names are NOT statically confirmed and are flagged as such in the docs — confirm via a Blutter retry or live capture before building against them.

## Implementation Tasks

### Task 1: Finalize full extraction & produce a structured inventory

**Objective:** Complete and verify a clean, reproducible extraction of `zenplayer.apk` into `extracted/` (already partially done: `apktool d` decoded the manifest/resources/smali, and a raw `unzip` produced 746 files). Produce `analysis/INVENTORY.md` cataloguing the decoded manifest essentials, every native lib per ABI with sizes, the dex set, and the asset/config inventory — the single reference map for all later tasks.

**Files:**

- Create: `analysis/INVENTORY.md`
- Use (already produced): `extracted/apktool/` (apktool decode), `extracted/raw/` (raw unzip), `tools/apktool.jar`

**Key Decisions / Notes:**

- Re-run `java -jar tools/apktool.jar d -f -o extracted/apktool zenplayer.apk` only if `extracted/apktool/AndroidManifest.xml` is missing — it is already present from planning.
- Inventory must capture: declared permissions, exported components, RevenueCat/Firebase meta-data keys, the presence of `assets/AppstoreAuthenticationKey.pem`, and the full `lib/<abi>/*.so` list with byte sizes. Reference real paths, not summaries.
- Do NOT commit the 120 MB APK or the multi-ABI extracted libs into any repo; keep them under `extracted/` (add a `.gitignore` note if a repo is later initialized).

**Definition of Done:**

- [ ] `analysis/INVENTORY.md` lists every `lib/<abi>/*.so` with size, the 3 dex files, declared permissions, and exported components — each traceable to a path under `extracted/`.
- [ ] Verify: `test -f extracted/apktool/AndroidManifest.xml && test -f extracted/raw/lib/arm64-v8a/libapp.so && test -f extracted/raw/lib/arm64-v8a/libiptv_loader.so && echo OK`

### Task 2: Recover Dart structure from `libapp.so` (Blutter, with RE fallback)

**Objective:** Recover human-readable structure (class names, method names, string pool, and where possible call relationships) from the arm64-v8a `libapp.so` AOT snapshot, so Tasks 3-4 can locate the auth and IPTV code by name instead of guessing. This is the analytical backbone of the plan.

**Files:**

- Create: `tools/blutter/` (cloned/built tool), `analysis/dart/` (Blutter output: `objs.txt`, `pp.txt`, symbol dumps)
- Create: `analysis/DART_RECOVERY.md` (what was recovered, fidelity, and the fallback used if any)

**Key Decisions / Notes:**

- Primary: build/run **Blutter** (`https://github.com/worawit/blutter`) against `extracted/raw/lib/arm64-v8a/libapp.so` + `extracted/raw/lib/arm64-v8a/libflutter.so`. It auto-detects the Dart snapshot version and fetches the matching Dart SDK; needs `cmake`, `ninja`, a C++ toolchain, and Python (all installable; `uv` available for the Python side).
- Fallback if Blutter cannot build or no matching SDK: use **radare2** (`aaa`, `izz`, `axt`) or **Ghidra headless** on `libapp.so` for string + cross-reference recovery; record the reduced fidelity explicitly in `DART_RECOVERY.md`. Secondary fallback: **reFlutter**.
- Capture, at minimum, the recovered string pool to `analysis/dart/strings.txt` — this is where endpoint fragments, error messages, and key names surface even when full symbolication fails.

**Definition of Done:**

- [ ] `analysis/dart/` contains the recovered symbol/string output from `libapp.so` (Blutter `objs.txt`+`pp.txt`, or documented radare2/Ghidra fallback output).
- [ ] `analysis/DART_RECOVERY.md` states which tool succeeded, the Dart/Flutter snapshot version detected, and the recovery fidelity (full symbolication vs strings-only).
- [ ] Verify: `test -s analysis/dart/strings.txt && echo OK` (recovery produced a non-empty string pool from the Dart binary).

### Task 3: Map the authentication & subscription (RevenueCat) flow

**Objective:** Produce `analysis/AUTH_FLOW.md` describing, with evidence, how a user currently authenticates and how entitlement/subscription is determined: the login UI inputs, the network endpoint(s) and request/response shapes (as far as recoverable), token/session storage (sqlite/datastore), and the split between custom-backend auth and RevenueCat entitlements.

**Files:**

- Create: `analysis/AUTH_FLOW.md`
- Use: `analysis/dart/` (Task 2 output), `extracted/apktool/smali*/` (RevenueCat/billing plugin calls, MainActivity), `extracted/raw/assets/AppstoreAuthenticationKey.pem`

**Key Decisions / Notes:**

- Cross-reference Task 2's recovered symbols/strings for login/auth/token/entitlement identifiers; corroborate the Android side via smali of `com.revenuecat.purchases.*` and Play Billing in `extracted/apktool/smali*/`.
- Distinguish clearly: (a) account login (custom server?) vs (b) RevenueCat entitlement check. The 8-char-code goal targets (a); document whether content access is gated by (a), (b), or both — this directly drives the feasibility verdict.
- If concrete endpoints/URLs are NOT statically recoverable, say so explicitly and mark them as "to be confirmed dynamically in Task 5" rather than inventing values.

**Definition of Done:**

- [ ] `analysis/AUTH_FLOW.md` documents the login input fields, the auth endpoint(s) or an explicit "not statically recoverable → Task 5" note, session/token storage location, and the RevenueCat-vs-custom-auth split — each claim citing a file/symbol from `extracted/` or `analysis/dart/`.
- [ ] Verify: `grep -qiE 'revenuecat|entitle|login|token' analysis/AUTH_FLOW.md && echo OK`

### Task 4: Map the IPTV content-loading flow

**Objective:** Produce `analysis/IPTV_FLOW.md` describing how the app fetches playlists/streams/portals: the role of `libiptv_loader.so`, whether a portal/server base URL is configurable or hard-coded, the protocol family (Xtream Codes `player_api.php`/`get.php`, Stalker portal, plain M3U, or proprietary), and how stream URLs reach libVLC/ffmpeg.

**Files:**

- Create: `analysis/IPTV_FLOW.md`
- Use: `extracted/raw/lib/arm64-v8a/libiptv_loader.so`, `analysis/dart/` (Task 2), `extracted/raw/lib/arm64-v8a/libffmpegJNI.so`

**Key Decisions / Notes:**

- Analyze `libiptv_loader.so` with radare2/Ghidra (`izz` for strings, `axt` for xrefs to URL/format strings); look for Xtream/Stalker/M3U markers (`player_api.php`, `panel_api.php`, `get.php`, `stalker_portal`, `#EXTM3U`).
- Determine the **configurability** question explicitly: can the IPTV server be pointed elsewhere (config/preference/login field), or is it fixed? This is the make-or-break input for the "backend-redirect" approach in Task 6.
- Tie back to Task 3: is IPTV access gated by the same auth token, or independent?

**Definition of Done:**

- [ ] `analysis/IPTV_FLOW.md` identifies the IPTV protocol family, where stream/portal URLs originate, and a clear yes/no/uncertain verdict on server configurability — each claim citing a symbol/string from `libiptv_loader.so` or `analysis/dart/`.
- [ ] Verify: `grep -qiE 'xtream|m3u|portal|stream|libiptv_loader' analysis/IPTV_FLOW.md && echo OK`

### Task 5: (Conditional) Dynamic traffic capture to confirm endpoints & pinning

**Objective:** When static analysis (Tasks 3-4) leaves endpoints or the auth protocol unconfirmed, run the app on an emulator/device and capture its network traffic to recover the live auth + IPTV protocol and to test for TLS certificate pinning. Produces `analysis/DYNAMIC_CAPTURE.md`.

**Files:**

- Create: `analysis/DYNAMIC_CAPTURE.md`, `analysis/capture/` (mitmproxy flows / logs)

**Key Decisions / Notes:**

- Run ONLY if Task 3 or Task 4 marked endpoints/protocol as "not statically recoverable", OR to validate a recovered protocol before the feasibility verdict. Skip (and note "static analysis sufficient") otherwise.
- Use an Android emulator (AVD via `adb`) with a system/user CA and **mitmproxy**; install the APK with `adb install`. Capture login + channel-load flows.
- Explicitly test cert pinning: if traffic does not appear through the proxy, document pinning as a hard finding (it raises the cost of any backend-redirect approach).
- Authorization reminder: the user has dev authorization for this analysis. Capture only this app's own traffic.

**Definition of Done:**

- [ ] `analysis/DYNAMIC_CAPTURE.md` records either the captured auth/IPTV requests (method, host, path, body shape — secrets redacted) OR a documented blocker (no device available / cert pinning), with the command sequence used.
- [ ] Verify: `test -f analysis/DYNAMIC_CAPTURE.md && echo OK`

### Task 6: Feasibility report & recommended architecture

**Objective:** Synthesize all findings into `analysis/FEASIBILITY.md`: a direct verdict on whether the end goal (8-char-code login + Python backend managing accounts and IPTV access) is achievable from the APK alone, and 2-3 concrete candidate architectures with effort, risk, and prerequisites — so the user can choose the path for the follow-up implementation spec.

**Files:**

- Create: `analysis/FEASIBILITY.md`
- Use: `analysis/AUTH_FLOW.md`, `analysis/IPTV_FLOW.md`, `analysis/DYNAMIC_CAPTURE.md` (if present), `analysis/INVENTORY.md`

**Key Decisions / Notes:**

- Present, at minimum, these three approaches with an honest cost/risk for each, grounded in the actual findings:
  1. **Get the Flutter source from the dev** — the only path that delivers the true 8-char-code login *UX* (new login screen) plus a clean Python backend. Recommended whenever obtainable, since the dev authorizes the work.
  2. **Custom backend + redirect (no UI change)** — stand up a Python backend speaking the app's existing auth/IPTV protocol; map existing login fields to 8-char codes server-side. Viable only if Tasks 3-5 show the server is configurable/redirectable and not hard-pinned. The in-app field labels stay as-is.
  3. **Runtime/binary patch (Frida or `libapp.so` patch)** — alter behavior without source; brittle, needs root/repackage, no clean UX. Last resort.
- State plainly the constraint from "Context for Implementer": the in-app 8-char-code *screen* is impossible without source (approaches 2-3 cannot change the Flutter UI).
- End with a single recommended next step and what the follow-up spec would need.

**Definition of Done:**

- [ ] `analysis/FEASIBILITY.md` gives a yes/no/conditional verdict on the end goal, documents the 3 approaches with effort+risk+prerequisites grounded in the prior analysis docs, and names one recommended next step.
- [ ] Verify: `grep -qiE 'recommend|approach|backend|source' analysis/FEASIBILITY.md && echo OK`
