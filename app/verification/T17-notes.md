# Task 17 (Downloads) verification notes
- DownloadController downloads VOD/episode URLs to getApplicationDocumentsDirectory()
  (app-internal -> NO storage permission on Android 13/14, the emulator target),
  tracks status/bytes/progress in the drift Downloads table, supports cancel +
  delete (removes file + row), and exposes localPath() for offline play.
- Download action added to VOD detail (Télécharger button); Downloads screen
  added to the AppBar with progress, delete, and tap-to-play-offline (plays the
  local file path through the same PlayerScreen).
- Live verification of an end-to-end download requires an Xtream VOD source
  (M3U sources expose no downloadable VOD by protocol). The download path uses
  dio.download streamed to disk (no UI block) + drift persistence; analyze clean,
  full suite green (50 tests).
