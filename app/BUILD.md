# Building Deko IPTV

## Prerequisites
- Flutter SDK pinned via FVM: `fvm use 3.32.5` (Flutter 3.32.5 / Dart 3.8.1).
  Direct path: `~/fvm/versions/3.32.5/bin/{flutter,dart}`.
- Android SDK with platform 36 + NDK 27.0.12077973 (already configured here).

## Build-time configuration (--dart-define)
The app reads these at build time (kept out of source control):

| Define | Source | Required |
|--------|--------|----------|
| `ZEN_ANON_KEY` | `../backend/.env` → `ANON_KEY` (self-hosted Supabase anon key) | **yes** |
| `ZEN_BACKEND` | defaults to `http://iptv.sarlnsi.ovh:4500` | no |
| `TMDB_API_KEY` | a TMDB v3 API key for artwork/overview enrichment | no (graceful fallback) |

## Debug build / run
```bash
ANON=$(grep '^ANON_KEY=' ../backend/.env | cut -d= -f2-)
fvm flutter run --dart-define=ZEN_ANON_KEY="$ANON"
# or:
fvm flutter build apk --debug --dart-define=ZEN_ANON_KEY="$ANON"
```

## Release build
```bash
ANON=$(grep '^ANON_KEY=' ../backend/.env | cut -d= -f2-)
fvm flutter build apk --release \
  --dart-define=ZEN_ANON_KEY="$ANON" \
  [--dart-define=TMDB_API_KEY=<key>]
# -> build/app/outputs/flutter-apk/app-release.apk
```

### Signing
- **With a real keystore** (recommended for distribution): copy
  `android/key.properties.example` → `android/key.properties` and fill it in.
  Generate a keystore:
  ```bash
  keytool -genkey -v -keystore ~/zen-release.jks -keyalg RSA -keysize 2048 \
    -validity 10000 -alias zen
  ```
  When `key.properties` exists, the release build is signed with it.
- **Without a keystore**: the release build falls back to **debug signing** so
  the APK still installs for testing. Do NOT distribute a debug-signed APK.

## Install on a device / emulator
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Recompiling in Android Studio
Open `app/` in Android Studio, set the Flutter SDK to `~/fvm/versions/3.32.5`,
and add the `--dart-define` values under Run/Debug Configurations → "Additional
run args". Then Build → Flutter → Build APK.
