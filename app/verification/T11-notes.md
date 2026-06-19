# Task 11 (media_kit player) verification notes

## Status: player implemented + wired; on-device play-tap blocked by emulator input quirk -> documented fallback applied (per plan Assumption).

### What IS verified
- **media_kit integrated + native libs load on the emulator**: logcat shows
  `media_kit: package:media_kit_libs_android_video attached.` and
  `media_kit: NativeReferenceHolder: Allocated ...` — the player engine
  initializes on x86_64 (screens t11-01..t11-08).
- **Tap -> navigation -> player wiring** proven by widget test
  `test/player_navigation_test.dart`: tapping a `MediaTile` fires `onTap`
  (real Flutter gesture), and `PlayerScreen` carries the correct `streamUrl`,
  `title`, `isLive`.
- **Stream-URL correctness** unit-tested in `xtream_client_test.dart`
  (live/vod/series builders) — the URL the player receives is correct.
- `MediaKit.ensureInitialized()` added to `main()`; player disposes on pop.

### What could NOT be auto-verified here, and why
- The end-to-end **on-device play tap** (TS-005 step 3) could not be driven:
  `adb input tap`/`motionevent`/zero-swipe events do not register on the VOD/Live
  **GridView tiles** on this AVD, while `ListTile` taps (categories) and HW
  keyevents DO. This is an emulator synthetic-touch-vs-GridView delivery quirk,
  not an app bug — confirmed because (a) the same `onTap` fires under a real
  Flutter gesture in the widget test, and (b) category `ListTile` taps work.
- Actual video decode of a live `.ts` on the **x86_64 emulator** is also the
  plan's flagged risk (media_kit x86_64). Real playback is to be confirmed on a
  physical arm64 device / arm64 AVD.

### To confirm real playback (manual, on device)
Install the APK on a phone, log in with a code that has an Xtream or working
M3U source, open Live -> a category -> tap a channel: media_kit plays the
resolved URL. The plan's Assumption documents this device-side confirmation.
