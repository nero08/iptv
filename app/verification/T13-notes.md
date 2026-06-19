# Task 13 (EPG) verification notes
- `get_short_epg` base64 title + epoch parsing -> now/next: verified by
  test/epg_service_test.dart (5 tests, the primary DoD).
- now/next wired into the live channel tile subtitle (Xtream channels); shows
  the current programme title. M3U sources have no EPG (guarded).
- Emulator EPG display requires an EPG-capable Xtream source; per plan, the
  fixture unit test is the documented verification when no such source is on hand.
