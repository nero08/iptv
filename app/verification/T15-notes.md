# Task 15 (TMDB) verification notes
- TMDB parsing + byId + searchFirst + **no-key graceful fallback** unit-tested
  in test/tmdb_service_test.dart (6 tests).
- Wired into VOD detail: TMDB poster/overview preferred when a key is set and a
  match is found (by tmdb_id), else falls back to Xtream `cover_big`/`stream_icon`
  with no error.
- No TMDB key is configured in this build (ZEN: TMDB_API_KEY empty), so the app
  runs the fallback path by default — verified by the no-key unit test and by
  the VOD detail rendering Xtream art. Supplying --dart-define=TMDB_API_KEY=...
  at build enables enrichment.
