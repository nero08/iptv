# Task 19 — Release build E2E verification

**Date:** 2026-06-01  **Build:** release APK, `app-release.apk` (116.3 MB)
**Device:** AVD `Pixel_3a_API_34_extension_level_7_x86_64` (emulator-5554)
**Backend:** `http://iptv.sarlnsi.ovh:4500` (live)  **Test code:** `<test-access-code>` (max_devices=3, backend M3U source "Free TV (iptv-org)")

## Commands
```bash
ANON=$(grep '^ANON_KEY=' ../backend/.env | cut -d= -f2-)
fvm flutter build apk --release --dart-define=ZEN_ANON_KEY="$ANON"   # exit 0
adb uninstall app.zeniptv.mobile ; adb install -r build/app/outputs/flutter-apk/app-release.apk   # Success
```
`flutter analyze lib test` → No issues found. `flutter test` → **51/51 passed**.

## Happy path (release APK, live backend)
| # | Step | Evidence | Result |
|---|------|----------|--------|
| 1 | Build release APK | build exit 0, 116.3 MB | ✅ |
| 2 | Install on emulator | `Success` | ✅ |
| 3 | Login screen renders | `01-login.png` ("Zen Player", "Entrez votre code d'accès", "Se connecter") | ✅ |
| 4 | Enter `<test-access-code>`, submit | `02-code-entered.png` (button enabled) | ✅ |
| 5 | Redeem → source received → catalog loaded | `03-home-live.png` (live categories + bottom nav TV/Films/Séries/Recherche) | ✅ TS-001/TS-004/TS-005-1 |
| 6 | Kill + relaunch → session restored | `06-restored.xml` (straight to Home, no re-login) | ✅ TS-001-3 |
| 7 | Category → channel grid (logos) | `04-channels.png` (100% News, Asharq, BFM Business, CNBC …) | ✅ TS-005-2 |
| 8 | Tap channel → **player opens** | `16-player-video.png` (PlayerScreen: back + "100% News (576p)"); libmpv log `VideoOutput.Resize {width:768,height:576}` | ✅ TS-005-3 |
| 9 | Search "news" → tappable results | `10-search.png` ("Chaînes (50)") | ✅ TS (search) |
| 10 | Back from player → clean dispose | returned to grid, pid alive, no flutter errors | ✅ (no leak/crash) |

## Bug found & fixed during this verification
`LiveChannel.fromJson` dropped `direct_url` → M3U channels rehydrated from cache had `directUrl == null` → `liveUrl` fell to the Xtream branch and threw on `serverUrl!` (null for M3U), **silently** in the tap handler. Symptom: tapping any channel did nothing (release build logged only `Another exception was thrown: Instance of 'DiagnosticsProperty<void>'`). Fixed in `lib/iptv/models.dart`; regression test added in `test/iptv_repository_test.dart`. After the fix, the grid tile → player path works (step 8).

## Notes
- The video surface renders **black** on this emulator because libmpv logs "Emulator detected. Enforcing S/W rendering." The player chrome + the `VideoOutput.Resize` to the stream's native 768×576 confirm the stream connected and was demuxed; pixel output is an emulator software-renderer limitation, not an app issue (matches plan Assumption for Tasks 11/19).
- Signing: no `android/key.properties` present → release build falls back to **debug signing** (per `BUILD.md`); installs for testing, must not be distributed as-is.
- VOD/Series/EPG/Downloads exercise an **Xtream** source; the test code's source is M3U (no VOD/Series/EPG), so those paths are covered by unit tests + the live M3U live-TV path here (documented plan Assumption).
