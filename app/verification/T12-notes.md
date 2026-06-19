# Task 12 (Series) verification notes
- Séries tab wired into the shell; screenshot t12-01-series.png.
- With the M3U test source, Series is correctly unavailable ("Cette source ne
  propose pas de séries") — source-kind guard verified.
- Full series grid + season/episode detail (TS-006 step 2) needs an **Xtream**
  source (plan Assumption). The path mirrors VOD/Live (verified end-to-end with
  real data); `get_series_info` -> seasons/episodes parsing is unit-tested in
  test/xtream_client_test.dart. Season selector + episode->player wired.
