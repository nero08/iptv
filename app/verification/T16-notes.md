# Task 16 (Profiles + Favorites + History) verification notes
- Per-profile favorites + watch-history + profile CRUD: 4 unit tests in
  test/favorites_profiles_test.dart (per-profile scoping, toggle on/off,
  resume round-trip, delete-cascade).
- Emulator (TS-007): favorited "100% News" via the tile star -> it appears in
  the Favoris screen with an amber star (screens t16-01-fav.png, t16-03-favorites.png).
- Profiles screen (create/switch/delete) wired into the AppBar; active profile
  initialised to the first profile; default profile auto-created on first run.
- VOD resume: player reports progress via onProgress -> saveProgress; reopening
  passes startPositionSecs from resumePosition (wired in vod_detail _play).
