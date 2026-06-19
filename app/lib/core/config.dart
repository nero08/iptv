/// App-wide configuration. Values are supplied at build time via `--dart-define`
/// to keep them out of source control.
///
/// Threat-model note: `--dart-define` is NOT a secret store — `ZEN_ANON_KEY` is
/// embedded as a plaintext string in the compiled APK and is extractable
/// (`strings`/`apktool`). This is acceptable here because the anon key only
/// reaches SECURITY DEFINER RPCs (`redeem_access_code`, `get_sources_for_code`)
/// that are gated by a code+device pair; it grants no direct table access.
/// (Backend rate-limiting on redeem is tracked as a deferred idea.)
class AppConfig {
  /// Supabase/Kong base URL. The app talks only to `/rest/v1/rpc/*`.
  static const String backendUrl = String.fromEnvironment(
    'ZEN_BACKEND',
    defaultValue: 'http://iptv.sarlnsi.ovh:4500',
  );

  /// Supabase anon key (public client JWT). Required header `apikey` on RPCs.
  static const String anonKey = String.fromEnvironment(
    'ZEN_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzgwMjY2NzMxLCJleHAiOjIwOTU2MjY3MzF9.4csNWdv02tvU6xdS1BIIZJCfPPJFhZGNmyIGf7-rssg',
  );

  /// Optional TMDB v3 API key. Empty -> TMDB enrichment is skipped gracefully.
  static const String tmdbKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: '',
  );

  /// The exact access-code alphabet used by the backend `gen_access_code`
  /// (excludes look-alikes 0/O/1/I). Used for client-side shape validation.
  static const String codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int codeLength = 8;
}
