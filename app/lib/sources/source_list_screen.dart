import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_source_screen.dart';
import 'source_models.dart';
import 'source_repository.dart';

/// Lists all sources (admin-pushed + local). Backend sources are read-only;
/// local ones can be deleted. Tapping a source selects it as active.
class SourceListScreen extends ConsumerWidget {
  const SourceListScreen({super.key, this.onSelect});

  /// Called when a source is tapped (e.g. to set it active and browse).
  final void Function(IptvSource source)? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(sourceListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sources IPTV')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddSourceScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (sources) {
          if (sources.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(sourceListProvider),
            child: ListView.separated(
              itemCount: sources.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = sources[i];
                return ListTile(
                  leading: Icon(
                      s.kind == SourceKind.xtream ? Icons.dns : Icons.playlist_play),
                  title: Text(s.name),
                  subtitle: Text(
                    '${s.kind == SourceKind.xtream ? 'Xtream' : 'M3U'} · '
                    '${s.displayEndpoint}'
                    '${s.isReadOnly ? ' · fourni' : ''}',
                  ),
                  trailing: s.isReadOnly
                      ? const Icon(Icons.lock_outline, size: 18)
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ref
                                .read(sourceRepositoryProvider)
                                .removeLocal(s.id);
                            ref.invalidate(sourceListProvider);
                          },
                        ),
                  onTap: onSelect == null ? null : () => onSelect!(s),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.playlist_add, size: 56, color: Colors.white24),
            const SizedBox(height: 12),
            Text('Aucune source', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Ajoutez votre portail Xtream ou une playlist M3U.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
