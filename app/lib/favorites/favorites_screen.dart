import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'favorites_controller.dart';

/// Favorites for the active profile, grouped by type.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favsAsync = ref.watch(favoritesListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Favoris')),
      body: favsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (favs) {
          if (favs.isEmpty) {
            return const Center(
                child: Text('Aucun favori',
                    style: TextStyle(color: Colors.white54)));
          }
          return ListView.builder(
            itemCount: favs.length,
            itemBuilder: (context, i) {
              final f = favs[i];
              return ListTile(
                leading: Icon(_iconFor(f.type)),
                title: Text(f.title),
                subtitle: Text(_labelFor(f.type)),
                trailing: IconButton(
                  icon: const Icon(Icons.star, color: Colors.amber),
                  onPressed: () async {
                    await ref.read(favoritesControllerProvider).toggle(
                          profileId: f.profileId,
                          itemKey: f.itemKey,
                          type: f.type,
                          title: f.title,
                        );
                    ref.invalidate(favoritesListProvider);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconFor(String type) => switch (type) {
        'vod' => Icons.movie_outlined,
        'series' => Icons.video_library_outlined,
        _ => Icons.live_tv,
      };

  String _labelFor(String type) => switch (type) {
        'vod' => 'Film',
        'series' => 'Série',
        _ => 'Chaîne',
      };
}
