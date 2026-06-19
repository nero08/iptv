import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/player_screen.dart';
import 'browse_providers.dart';
import 'search_providers.dart';
import 'vod_detail_screen.dart';
import 'series_detail_screen.dart';

/// Search tab: queries the cached catalog (live + VOD + series), grouped.
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            autofocus: false,
            decoration: const InputDecoration(
              hintText: 'Rechercher chaînes, films, séries…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) =>
                ref.read(searchQueryProvider.notifier).state = v,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<SearchKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SearchKind.all, label: Text('Tout')),
                ButtonSegment(
                    value: SearchKind.live,
                    label: Text('TV'),
                    icon: Icon(Icons.live_tv)),
                ButtonSegment(
                    value: SearchKind.vod,
                    label: Text('Films'),
                    icon: Icon(Icons.movie_outlined)),
                ButtonSegment(
                    value: SearchKind.series,
                    label: Text('Séries'),
                    icon: Icon(Icons.video_library_outlined)),
              ],
              selected: {ref.watch(searchKindProvider)},
              onSelectionChanged: (s) =>
                  ref.read(searchKindProvider.notifier).state = s.first,
            ),
          ),
        ),
        Expanded(
          child: resultsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur: $e')),
            data: (r) {
              if (r.isEmpty) {
                return const Center(
                    child: Text('Tapez pour rechercher',
                        style: TextStyle(color: Colors.white54)));
              }
              return ListView(
                children: [
                  if (r.live.isNotEmpty) ...[
                    _header('Chaînes (${r.live.length})'),
                    ...r.live.map((ch) => ListTile(
                          leading: const Icon(Icons.live_tv),
                          title: Text(ch.name),
                          onTap: () {
                            final src = ref.read(activeSourceProvider)!;
                            final url =
                                ref.read(iptvRepositoryProvider).liveUrl(src, ch);
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => PlayerScreen(
                                  streamUrl: url, title: ch.name, isLive: true),
                            ));
                          },
                        )),
                  ],
                  if (r.vod.isNotEmpty) ...[
                    _header('Films (${r.vod.length})'),
                    ...r.vod.map((v) => ListTile(
                          leading: const Icon(Icons.movie_outlined),
                          title: Text(v.name),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => VodDetailScreen(item: v))),
                        )),
                  ],
                  if (r.series.isNotEmpty) ...[
                    _header('Séries (${r.series.length})'),
                    ...r.series.map((s) => ListTile(
                          leading: const Icon(Icons.video_library_outlined),
                          title: Text(s.name),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => SeriesDetailScreen(item: s))),
                        )),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _header(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white70)),
      );
}
