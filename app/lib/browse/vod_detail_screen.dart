import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../favorites/favorites_controller.dart';
import '../downloads/download_controller.dart';
import '../iptv/models.dart';
import '../player/player_screen.dart';
import '../profiles/profile_controller.dart';
import 'browse_providers.dart';

/// Movie detail: poster + metadata (from get_vod_info) + Play.
/// TMDB enrichment (Task 15) overlays richer artwork/overview when available.
class VodDetailScreen extends ConsumerWidget {
  const VodDetailScreen({super.key, required this.item});
  final VodItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(vodInfoProvider(item.streamId));
    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: infoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // If detail fetch fails we can still play with the catalog data.
        error: (e, _) => _body(context, ref, null),
        data: (info) => _body(context, ref, info),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, VodInfo? info) {
    // TMDB enrichment (graceful: null when no key / no match -> Xtream art).
    final tmdb = ref
        .watch(tmdbMovieProvider(item.tmdbId ?? info?.tmdbId))
        .maybeWhen(data: (m) => m, orElse: () => null);
    final poster = tmdb?.posterUrl ?? info?.coverBig ?? item.icon;
    final overview = tmdb?.overview ?? info?.plot;
    final ext = info?.containerExtension ?? item.containerExtension ?? 'mp4';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 180,
                child: (poster != null && poster.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: poster,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _ph(),
                        placeholder: (_, __) => _ph(),
                      )
                    : _ph(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (info?.genre != null) _meta('Genre', info!.genre!),
                  if (info?.releaseDate != null)
                    _meta('Sortie', info!.releaseDate!),
                  if (info?.durationSecs != null)
                    _meta('Durée', _fmtDuration(info!.durationSecs!)),
                  if (item.rating != null) _meta('Note', item.rating!),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _play(context, ref, ext),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Lecture'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _download(context, ref, ext),
              icon: const Icon(Icons.download),
              label: const Text('Télécharger'),
            ),
          ],
        ),
        if (overview != null) ...[
          const SizedBox(height: 20),
          Text('Synopsis', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(overview),
        ],
      ],
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref, String ext) async {
    final source = ref.read(activeSourceProvider)!;
    final url = ref.read(iptvRepositoryProvider).vodUrl(source, item.streamId, ext);
    final pid = ref.read(activeProfileIdProvider);
    final favs = ref.read(favoritesControllerProvider);
    final itemKey = FavoritesController.key(source.id, 'vod', '${item.streamId}');
    final resume =
        pid == null ? 0 : await favs.resumePosition(pid, itemKey);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        streamUrl: url,
        title: item.name,
        startPositionSecs: resume,
        onProgress: pid == null
            ? null
            : (pos, dur) => favs.saveProgress(
                  profileId: pid,
                  itemKey: itemKey,
                  positionSecs: pos.inSeconds,
                  durationSecs: dur?.inSeconds,
                ),
      ),
    ));
  }

  Future<void> _download(BuildContext context, WidgetRef ref, String ext) async {
    final source = ref.read(activeSourceProvider)!;
    final url = ref.read(iptvRepositoryProvider).vodUrl(source, item.streamId, ext);
    final itemKey = FavoritesController.key(source.id, 'vod', '${item.streamId}');
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Téléchargement démarré')));
    ref.read(downloadControllerProvider).start(
        itemKey: itemKey, title: item.name, url: url, ext: ext);
  }

  Widget _meta(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text('$label : $value',
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      );

  Widget _ph() => Container(
      color: const Color(0xFF23262E),
      child: const Icon(Icons.movie, color: Colors.white24, size: 36));

  static String _fmtDuration(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}min';
    return '${m}min';
  }
}
