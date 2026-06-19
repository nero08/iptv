import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../iptv/models.dart';
import '../sources/source_models.dart';
import 'browse_providers.dart';
import 'category_header.dart';
import 'media_tile.dart';
import 'vod_detail_screen.dart';

/// VOD tab: category list <-> movie grid, both inside the tab (persistent
/// bottom bar). Tapping a movie pushes its detail screen.
class VodScreen extends ConsumerWidget {
  const VodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(activeSourceProvider);
    if (source == null) {
      return const Center(child: Text('Sélectionnez une source'));
    }
    // M3U sources have no VOD section.
    if (source.kind == SourceKind.m3u) {
      return const Center(
        child: Text('Cette source ne propose pas de films (VOD).',
            style: TextStyle(color: Colors.white54)),
      );
    }
    final selected = ref.watch(vodSelectedCategoryProvider);
    if (selected != null) {
      return _VodGrid(category: selected);
    }
    final categoriesAsync = ref.watch(vodCategoriesProvider);
    return categoriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (categories) {
        if (categories.isEmpty) {
          return const Center(child: Text('Aucun film dans cette source'));
        }
        return ListView.builder(
          itemCount: categories.length,
          itemBuilder: (context, i) {
            final c = categories[i];
            return ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: Text(c.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  ref.read(vodSelectedCategoryProvider.notifier).state = c,
            );
          },
        );
      },
    );
  }
}

class _VodGrid extends ConsumerWidget {
  const _VodGrid({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(vodItemsProvider(category.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryHeader(
          title: category.name,
          onBack: () =>
              ref.read(vodSelectedCategoryProvider.notifier).state = null,
          categories: ref.watch(vodCategoriesProvider).valueOrNull,
          currentId: category.id,
          onSelectCategory: (c) =>
              ref.read(vodSelectedCategoryProvider.notifier).state = c,
        ),
        Expanded(
          child: itemsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur: $e')),
            data: (items) => GridView.builder(
              padding: const EdgeInsets.all(12),
              cacheExtent: 1200,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 0.55,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final v = items[i];
                return MediaTile(
                  title: v.name,
                  imageUrl: v.icon,
                  icon: Icons.movie,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => VodDetailScreen(item: v),
                  )),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
