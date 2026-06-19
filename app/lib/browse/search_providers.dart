import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../iptv/models.dart';
import 'browse_providers.dart';

/// Grouped search results across the cached catalog.
class SearchResults {
  SearchResults({this.live = const [], this.vod = const [], this.series = const []});
  final List<LiveChannel> live;
  final List<VodItem> vod;
  final List<SeriesItem> series;

  bool get isEmpty => live.isEmpty && vod.isEmpty && series.isEmpty;
  int get total => live.length + vod.length + series.length;
}

/// What the user wants to search. `all` searches every catalog type.
enum SearchKind { all, live, vod, series }

/// Raw query text, updated by the search field.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Selected search type (TV / Film / Série / Tout).
final searchKindProvider = StateProvider<SearchKind>((ref) => SearchKind.all);

/// Debounced query — only emits after the user stops typing (~300ms), so we
/// don't hit the DB on every keystroke (hot path).
final debouncedQueryProvider = StreamProvider.autoDispose<String>((ref) {
  final controller = StreamController<String>();
  Timer? timer;
  ref.listen<String>(searchQueryProvider, (_, next) {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 300), () => controller.add(next));
  }, fireImmediately: true);
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

final searchResultsProvider =
    FutureProvider.autoDispose<SearchResults>((ref) async {
  final query = ref.watch(debouncedQueryProvider).valueOrNull ?? '';
  if (query.trim().isEmpty) return SearchResults();
  final source = ref.watch(activeSourceProvider);
  if (source == null) return SearchResults();
  final repo = ref.watch(iptvRepositoryProvider);

  final kind = ref.watch(searchKindProvider);
  final wantLive = kind == SearchKind.all || kind == SearchKind.live;
  final wantVod = kind == SearchKind.all || kind == SearchKind.vod;
  final wantSeries = kind == SearchKind.all || kind == SearchKind.series;

  return SearchResults(
    live: wantLive
        ? (await repo.search(source.id, 'live', query))
            .map((r) =>
                LiveChannel.fromJson(jsonDecode(r.payload) as Map<String, dynamic>))
            .toList()
        : const [],
    vod: wantVod
        ? (await repo.search(source.id, 'vod', query))
            .map((r) =>
                VodItem.fromJson(jsonDecode(r.payload) as Map<String, dynamic>))
            .toList()
        : const [],
    series: wantSeries
        ? (await repo.search(source.id, 'series', query))
            .map((r) =>
                SeriesItem.fromJson(jsonDecode(r.payload) as Map<String, dynamic>))
            .toList()
        : const [],
  );
});
