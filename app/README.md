# Deko IPTV (zen_player)

IPTV player app — rebuilt from scratch. Logs in with an **8-character access code**
validated against the self-hosted Supabase backend (`http://iptv.sarlnsi.ovh:4500`),
plays Xtream Codes + M3U sources. `applicationId = app.zeniptv.mobile`.

## Toolchain

The shared system Flutter (`~/development/flutter`) is 3.7.5 (too old for media_kit /
recent plugins) and is used by other projects, so this project pins its own SDK via **FVM**:

```
fvm use 3.32.5    # Flutter 3.32.5 / Dart 3.8.1 (already installed in ~/fvm/versions)
```

Run all commands through the pinned SDK. Either:
- `fvm flutter <cmd>` (if `fvm` is on PATH), or
- direct: `~/fvm/versions/3.32.5/bin/flutter <cmd>` / `~/fvm/versions/3.32.5/bin/dart <cmd>`

Android Studio: set the Flutter SDK path to `~/fvm/versions/3.32.5`.

## Build / run

```bash
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs   # drift / freezed / json codegen
fvm flutter analyze
fvm flutter test

# The Supabase anon key is supplied at build time (kept out of source):
#   anon key = ANON_KEY in ../backend/.env
fvm flutter run --dart-define=ZEN_ANON_KEY=<anon> [--dart-define=TMDB_API_KEY=<key>]
fvm flutter build apk --release --dart-define=ZEN_ANON_KEY=<anon>
```

## Code generation

This project uses `drift` (DB), `freezed` (sealed state) and `json_serializable`.
After editing any `@DriftDatabase`, `@freezed`, or `@JsonSerializable` declaration,
re-run `fvm dart run build_runner build --delete-conflicting-outputs`.
