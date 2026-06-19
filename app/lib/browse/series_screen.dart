import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../iptv/models.dart';
import '../sources/source_models.dart';
import 'browse_providers.dart';
import 'category_header.dart';
import 'media_tile.dart';
import 'series_detail_screen.dart';

/// Series tab: category list <-> series grid, both inside the tab (persistent
/// bottom bar). Tapping a series pushes its detail (seasons/episodes).
class SeriesScreen extends ConsumerWidget {
  const SeriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(activeSourceProvider);
    if (source == null) {
      return const Center(child: Text('Sélectionnez une source'));
    }
    if (source.kind == SourceKind.m3u) {
      return const Center(
        child: Text('Cette source ne propose pas de séries.',
            style: TextStyle(color: Colors.white54)),
      );
    }
    final selected = ref.watch(seriesSelectedCategoryProvider);
    if (selected != null) {
      return _SeriesGrid(category: selected);
    }
    final categoriesAsync = ref.watch(seriesCategoriesProvider);
    return categoriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erreur: $e')),
      data: (categories) {
        if (categories.isEmpty) {
          return const Center(child: Text('Aucune série dans cette source'));
        }
        return ListView.builder(
          itemCount: categories.length,
          itemBuilder: (context, i) {
            final c = categories[i];
            return ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(c.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  ref.read(seriesSelectedCategoryProvider.notifier).state = c,
            );
          },
        );
      },
    );
  }
}

class _SeriesGrid extends ConsumerWidget {
  const _SeriesGrid({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(seriesItemsProvider(category.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryHeader(
          title: category.name,
          onBack: () =>
              ref.read(seriesSelectedCategoryProvider.notifier).state = null,
          categories: ref.watch(seriesCategoriesProvider).valueOrNull,
          currentId: category.id,
          onSelectCategory: (c) =>
              ref.read(seriesSelectedCategoryProvider.notifier).state = c,
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
                final s = items[i];
                return MediaTile(
                  title: s.name,
                  imageUrl: s.cover,
                  icon: Icons.video_library,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SeriesDetailScreen(item: s),
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
