# Task 10 (VOD) verification notes

- VOD tab wired into the home shell bottom-nav; screenshot `t10-01-vod-tab.png`.
- With the available test source (a backend-assigned **M3U** playlist), VOD is
  correctly unavailable — the screen shows "Cette source ne propose pas de
  films (VOD)." This verifies the source-kind guard.
- Full VOD grid + movie-detail (TS-006 step 1) needs an **Xtream** portal
  (plan Assumption: a working Xtream source is required for VOD/Series content
  verification). The M3U test source has no VOD section by protocol.
- The VOD browse path is structurally identical to the Live path (categories ->
  grid via the same providers/`MediaTile`/`IptvRepository`), which IS verified
  end-to-end with real data in Task 9. `vod_info` parsing is unit-tested in
  `xtream_client_test.dart`. Detail screen + Play-URL building reuse the tested
  `vodUrl`/`vodInfo` repository methods.
- To complete a live VOD pass: assign an Xtream source to a code via the admin
  UI and re-run; the same screens will populate.
