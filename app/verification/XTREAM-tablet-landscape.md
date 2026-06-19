# Real Xtream portal test — Pixel Tablet, landscape

**Date:** 2026-06-01  **Device:** AVD `Zen_Tablet_API_34` (Pixel Tablet, 2560×1600 @ 320dpi), **landscape**.
**Portal:** `<xtream-host>` · user `<redacted>` (live IPTV credentials supplied by the user — not stored in these artifacts). App: release APK, logged in with the test access code, Xtream added as a local BYO source.

## Portal account (player_api.php)
- status **Active**, connections 0/1 (max 1), expires ~2026/2027, not trial.
- Catalog: **368 live categories / ~37,158 live channels**, **2 VOD categories / ~2,434 movies**, **0 series**.
- ⚠️ The portal sits behind "Proxyschield" which **403s a bare `curl` UA** but accepts any real UA — including dio's default `Dart/<ver> (dart:io)`. So the app works with no UA change needed (verified: add-source validation succeeded).

## Results (all in landscape)
| Step | Result | Evidence |
|------|--------|----------|
| Device-limit screen | PASS (live TS-003) | 4th device on a max=3 code → "Limite d'appareils atteinte", no crash (`tablet-01-devicelimit.png`) |
| Add Xtream source + validate | PASS | `fetchSourceInfo` against the real portal OK → "Ma source · Xtream · `<xtream-host>`" saved |
| Source switch | PASS | Home AppBar switcher → Xtream catalog loads |
| Catalog load | PASS | 368 live categories incl. Arabic RTL (روتانا, أطفال) rendered correctly (`tablet-12-xtream-live.png`) |
| Live → channel grid | PASS | DEUTSCHLAND 4K → DAS ERSTE/ARTE/ZDF with logos (`tablet-13-channels.png`) |
| **EPG now/next** | PASS | ARTE 4K tile shows current programme "Todesmelodie" (live `get_short_epg`) |
| Live playback | PASS | DAS ERSTE 4k → player, libmpv `VideoOutput.Resize 1280×720` (`tablet-14-player.png`) |
| VOD grid | PASS | CHINA category → 10 Lives / 14 Blades / 18 Grams of Love |
| **VOD detail (`get_vod_info`)** | PASS | 10 Lives: genre Animation/Comedy/Family/Fantasy, release 2024-04-18, rating 8.2, poster + full synopsis (`tablet-18-voddetail.png`) |
| VOD playback | PASS | Lecture → player, libmpv `VideoOutput.Resize 1920×1072` (1080p) |
| Séries (empty) | PASS | "Aucune série dans cette source" — graceful (portal has 0 series) |

Video surface renders black under the emulator's S/W renderer (libmpv "Emulator detected. Enforcing S/W rendering"); stream connection + native-resolution negotiation confirm playback. On real hardware the frame renders.

## Issue found & fixed
- The add-source **Xtream "Mot de passe" field was not masked** (`obscureText` missing) while the M3U URL field was — password shown in plaintext. Fixed in `lib/sources/add_source_screen.dart` (added `obscureText: true`). Takes effect on next build.

## Note
Cleared 3 stale emulator device registrations from code `<test-access-code>` (DB) to free a slot for the tablet.
