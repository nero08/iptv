import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../epg/epg_models.dart';
import '../epg/epg_service.dart';
import '../iptv/iptv_repository.dart';
import '../iptv/models.dart';
import '../iptv/xtream_client.dart';
import '../tmdb/tmdb_models.dart';
import '../tmdb/tmdb_service.dart';
import '../sources/source_models.dart';
import '../sources/source_repository.dart';

/// The IPTV repository (catalog cache + clients), wired to the app database.
final iptvRepositoryProvider = Provider<IptvRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return IptvRepository(db);
});

/// The currently-selected source. Null until the user picks one (or the only
/// source is auto-selected by the shell).
final activeSourceProvider = StateProvider<IptvSource?>((ref) => null);

/// Per-tab drill-in state: the category the user opened inside a browse tab.
/// Null = show the category list; non-null = show that category's grid. Kept
/// here (not local widget state) so the shell can manage Back centrally with a
/// single [PopScope] and the bottom bar stays persistent (no pushed route).
final liveSelectedCategoryProvider = StateProvider<Category?>((ref) => null);
final vodSelectedCategoryProvider = StateProvider<Category?>((ref) => null);
final seriesSelectedCategoryProvider = StateProvider<Category?>((ref) => null);

/// Ensures the active source's catalog cache is populated, then returns.
///
/// Cache-first: if the catalog is already cached it returns instantly (no
/// network) and kicks off a background refresh; only the very first load (empty
/// cache) blocks on the network. This is why relaunching the app is instant.
final catalogLoadProvider = FutureProvider.autoDispose<void>((ref) async {
  final source = ref.watch(activeSourceProvider);
  if (source == null) return;
  final repo = ref.watch(iptvRepositoryProvider);
  if (await repo.hasCatalog(source.id)) {
    // Show cached data immediately; silently refresh in the background.
    Future.microtask(
        () => ref.read(catalogRefreshProvider.notifier).refresh());
    return;
  }
  await repo.loadCatalog(source, force: true);
});

/// Drives the manual reload button and the silent background refresh. The bool
/// state is `true` while a refresh is in flight (button shows a spinner).
final catalogRefreshProvider =
    StateNotifierProvider<CatalogRefreshNotifier, bool>(
        (ref) => CatalogRefreshNotifier(ref));

class CatalogRefreshNotifier extends StateNotifier<bool> {
  CatalogRefreshNotifier(this._ref) : super(false);
  final Ref _ref;

  /// Re-download the active source's catalog (force) and refresh the
  /// cache-read providers so the UI updates. No-op if already refreshing or no
  /// active source. Failures keep the existing cache (no UI wipe).
  Future<void> refresh() async {
    if (state) return;
    final source = _ref.read(activeSourceProvider);
    if (source == null) return;
    state = true;
    try {
      await _ref.read(iptvRepositoryProvider).loadCatalog(source, force: true);
      _ref.invalidate(liveCategoriesProvider);
      _ref.invalidate(liveChannelsProvider);
      _ref.invalidate(vodCategoriesProvider);
      _ref.invalidate(vodItemsProvider);
      _ref.invalidate(seriesCategoriesProvider);
      _ref.invalidate(seriesItemsProvider);
    } finally {
      if (mounted) state = false;
    }
  }
}

// --- Live ------------------------------------------------------------------

final liveCategoriesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
  final source = ref.watch(activeSourceProvider);
  if (source == null) return const [];
  // Ensure catalog is loaded before reading categories.
  await ref.watch(catalogLoadProvider.future);
  return ref.watch(iptvRepositoryProvider).categories(source.id, 'live');
});

final liveChannelsProvider = FutureProvider.autoDispose
    .family<List<LiveChannel>, String?>((ref, categoryId) async {
  final source = ref.watch(activeSourceProvider);
  if (source == null) return const [];
  await ref.watch(catalogLoadProvider.future);
  return ref
      .watch(iptvRepositoryProvider)
      .liveChannels(source.id, categoryId: categoryId);
});

// --- VOD -------------------------------------------------------------------

final vodCategoriesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
  final source = ref.watch(activeSourceProvider);
  if (source == null) return const [];
  await ref.watch(catalogLoadProvider.future);
  return ref.watch(iptvRepositoryProvider).categories(source.id, 'vod');
});

final vodItemsProvider = FutureProvider.autoDispose
    .family<List<VodItem>, String?>((ref, categoryId) async {
  final source = ref.watch(activeSourceProvider);
  if (source == null) return const [];
  await ref.watch(catalogLoadProvider.future);
  return ref
      .watch(iptvRepositoryProvider)
      .vodItems(source.id, categoryId: categoryId);
});

final vodInfoProvider =
    FutureProvider.autoDispose.family<VodInfo, int>((ref, streamId) async {
  final source = ref.watch(activeSourceProvider);
  if (source == null) throw StateError('No active source');
  return ref.watch(iptvRepositoryProvider).vodInfo(source, streamId);
});

// --- Series ----------------------------------------------------------------

final seriesCategoriesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
  final source = ref.watch(activeSourceProvider);
  if (source == null) return const [];
  await ref.watch(catalogLoadProvider.future);
  return ref.watch(iptvRepositoryProvider).categories(source.id, 'series');
});

final seriesItemsProvider = FutureProvider.autoDispose
    .family<List<SeriesItem>, String?>((ref, categoryId) async {
  final source = ref.watch(activeSourceProvider);
  if (source == null) return const [];
  await ref.watch(catalogLoadProvider.future);
  return ref
      .watch(iptvRepositoryProvider)
      .seriesItems(source.id, categoryId: categoryId);
});

final seriesInfoProvider =
    FutureProvider.autoDispose.family<SeriesInfo, int>((ref, seriesId) async {
  final source = ref.watch(activeSourceProvider);
  if (source == null) throw StateError('No active source');
  return ref.watch(iptvRepositoryProvider).seriesInfo(source, seriesId);
});

// --- EPG --------------------------------------------------------------------

/// One [EpgService] per active Xtream source — holds the short-EPG TTL cache and
/// a single Dio/XtreamClient. NON-autoDispose so the cache survives grid scroll;
/// rebuilt only when the active source changes. Null for M3U / no source.
final epgServiceProvider = Provider<EpgService?>((ref) {
  final source = ref.watch(activeSourceProvider);
  if (source == null || source.kind != SourceKind.xtream) return null;
  return EpgService(XtreamClient(
    serverUrl: source.serverUrl!,
    username: source.username!,
    password: source.password!,
  ));
});

/// now/next EPG for a live channel (Xtream only). Returns an empty NowNext for
/// M3U sources or on failure. Reads the shared [epgServiceProvider] so repeated
/// tile rebuilds reuse the cache instead of issuing one HTTP call per rebuild.
final nowNextProvider =
    FutureProvider.autoDispose.family<NowNext, int>((ref, streamId) async {
  final epg = ref.watch(epgServiceProvider);
  if (epg == null) return NowNext();
  return epg.nowNext(streamId);
});

// --- TMDB -------------------------------------------------------------------

final tmdbServiceProvider = Provider<TmdbService>((ref) => TmdbService());

/// TMDB metadata for a movie by tmdb id; null when no key or no match.
final tmdbMovieProvider =
    FutureProvider.autoDispose.family<TmdbMeta?, int?>((ref, tmdbId) async {
  if (tmdbId == null) return null;
  return ref.watch(tmdbServiceProvider).byId('movie', tmdbId);
});
