// An IPTV source — either an Xtream Codes portal or an M3U playlist.
// Sources come from two origins: pushed by the backend (admin-assigned, read
// only in-app) or added locally by the user (BYO, editable). Both share this
// model so the rest of the app treats them uniformly.

enum SourceKind { xtream, m3u }

enum SourceOrigin { backend, local }

class IptvSource {
  IptvSource({
    required this.id,
    required this.origin,
    required this.kind,
    required this.name,
    this.serverUrl,
    this.username,
    this.password,
    this.m3uUrl,
  });

  final String id;
  final SourceOrigin origin;
  final SourceKind kind;
  final String name;

  // Xtream
  final String? serverUrl;
  final String? username;
  final String? password;

  // M3U
  final String? m3uUrl;

  bool get isReadOnly => origin == SourceOrigin.backend;

  /// Dedup key: same kind + endpoint + user identifies the same source
  /// regardless of origin (backend wins on conflict).
  String get dedupKey {
    if (kind == SourceKind.xtream) {
      return 'xtream|${_host(serverUrl)}|${username ?? ''}';
    }
    return 'm3u|${m3uUrl ?? ''}';
  }

  /// Host-only display for credential-bearing URLs (never show raw creds).
  String get displayEndpoint {
    if (kind == SourceKind.xtream) return _host(serverUrl);
    return _host(m3uUrl);
  }

  static String _host(String? url) {
    if (url == null || url.isEmpty) return '';
    final u = Uri.tryParse(url);
    if (u == null) return url;
    return u.host.isEmpty ? url : '${u.host}${u.hasPort ? ':${u.port}' : ''}';
  }

  static SourceKind kindFromString(String s) =>
      s == 'm3u' ? SourceKind.m3u : SourceKind.xtream;

  /// Build from a backend `get_sources_for_code` row.
  factory IptvSource.fromBackendRow(Map<String, dynamic> r) => IptvSource(
        id: 'backend_${r['id']}',
        origin: SourceOrigin.backend,
        kind: kindFromString((r['kind'] ?? 'xtream').toString()),
        name: (r['name'] ?? 'Source').toString(),
        serverUrl: r['server_url'] as String?,
        username: r['username'] as String?,
        password: r['password'] as String?,
        m3uUrl: r['m3u_url'] as String?,
      );
}
