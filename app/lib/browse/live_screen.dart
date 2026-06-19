import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../favorites/favorites_controller.dart';
import '../iptv/models.dart';
import '../player/player_screen.dart';
import '../profiles/profile_controller.dart';
import '../sources/source_models.dart';
import 'browse_providers.dart';
import 'category_header.dart';
import 'media_tile.dart';

/// Live tab: category list <-> channel grid, both rendered inside the tab so
/// the persistent bottom bar stays visible (no pushed route). Drill-in state
/// lives in [liveSelectedCategoryProvider]; Back is handled centrally by the
/// shell's PopScope.
class LiveScreen extends ConsumerWidget {
  const LiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(activeSourceProvider);
    if (source == null) {
      return const Center(child: Text('Sélectionnez une source'));
    }
    final selected = ref.watch(liveSelectedCategoryProvider);
    if (selected != null) {
      return _LiveGrid(category: selected, source: source);
    }
    final categoriesAsync = ref.watch(liveCategoriesProvider);
    return categoriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorRetry(message: '$e', onRetry: () {
        ref.invalidate(catalogLoadProvider);
        ref.invalidate(liveCategoriesProvider);
      }),
      data: (categories) {
        if (categories.isEmpty) {
          return const Center(child: Text('Aucune chaîne dans cette source'));
        }
        return ListView.builder(
          itemCount: categories.length,
          itemBuilder: (context, i) {
            final c = categories[i];
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(c.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  ref.read(liveSelectedCategoryProvider.notifier).state = c,
            );
          },
        );
      },
    );
  }
}

class _LiveGrid extends ConsumerWidget {
  const _LiveGrid({required this.category, required this.source});
  final Category category;
  final IptvSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(liveChannelsProvider(category.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryHeader(
          title: category.name,
          onBack: () =>
              ref.read(liveSelectedCategoryProvider.notifier).state = null,
          categories: ref.watch(liveCategoriesProvider).valueOrNull,
          currentId: category.id,
          onSelectCategory: (c) =>
              ref.read(liveSelectedCategoryProvider.notifier).state = c,
        ),
        Expanded(
          child: channelsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur: $e')),
            data: (channels) => GridView.builder(
              padding: const EdgeInsets.all(12),
              // Build a couple of rows ahead so D-pad "down" finds the next row
              // (and only falls through to the bottom bar at the true last row).
              cacheExtent: 1200,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: channels.length,
              itemBuilder: (context, i) {
                final ch = channels[i];
                // now/next EPG for Xtream channels (streamId>0); empty otherwise.
                final nowTitle = ch.streamId > 0
                    ? ref.watch(nowNextProvider(ch.streamId)).maybeWhen(
                        data: (nn) => nn.now?.title, orElse: () => null)
                    : null;
                final pid = ref.watch(activeProfileIdProvider);
                final favKey = FavoritesController.key(source.id, 'live',
                    ch.streamId > 0 ? '${ch.streamId}' : ch.name);
                return MediaTile(
                  title: ch.name,
                  imageUrl: ch.icon,
                  subtitle: nowTitle,
                  aspectRatio: 1,
                  icon: Icons.live_tv,
                  onTap: () => _openPlayer(context, ref, channels, i),
                  // Long-press (or remote OK held) toggles favorite without
                  // needing to focus the star, which is not D-pad focusable.
                  onLongPress: pid == null
                      ? null
                      : () => _toggleFav(ref, pid, favKey, ch.name),
                  trailing: pid == null
                      ? null
                      : _FavStar(
                          profileId: pid,
                          itemKey: favKey,
                          type: 'live',
                          title: ch.name),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _openPlayer(
      BuildContext context, WidgetRef ref, List<LiveChannel> channels, int i) {
    final url = ref.read(iptvRepositoryProvider).liveUrl(source, channels[i]);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        streamUrl: url,
        title: channels[i].name,
        isLive: true,
        channels: channels,
        channelIndex: i,
        source: source,
      ),
    ));
  }

  Future<void> _toggleFav(
      WidgetRef ref, String pid, String favKey, String title) async {
    await ref
        .read(favoritesControllerProvider)
        .toggle(profileId: pid, itemKey: favKey, type: 'live', title: title);
    ref.invalidate(favoritesListProvider);
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.orangeAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

/// A favorite toggle star overlaid on a media tile.
///
/// Reactive to [favoritesListProvider] so it updates whether toggled from the
/// star itself (touch) or via the tile's long-press (remote). It is touch-only:
/// `canRequestFocus: false` keeps it out of the D-pad traversal so the remote
/// focuses the tile, not the star.
class _FavStar extends ConsumerWidget {
  const _FavStar(
      {required this.profileId,
      required this.itemKey,
      required this.type,
      required this.title});
  final String profileId;
  final String itemKey;
  final String type;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoritesListProvider).valueOrNull ?? const [];
    final isFav = favs.any((f) => f.itemKey == itemKey);
    return InkWell(
      canRequestFocus: false,
      onTap: () async {
        await ref.read(favoritesControllerProvider).toggle(
            profileId: profileId, itemKey: itemKey, type: type, title: title);
        ref.invalidate(favoritesListProvider);
      },
      child: Container(
        decoration:
            const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        padding: const EdgeInsets.all(4),
        child: Icon(isFav ? Icons.star : Icons.star_border,
            size: 18, color: isFav ? Colors.amber : Colors.white),
      ),
    );
  }
}
