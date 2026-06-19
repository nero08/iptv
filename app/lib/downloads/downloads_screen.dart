import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/player_screen.dart';
import 'download_controller.dart';

/// Lists downloads with status; completed items play offline from local file.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(downloadsListProvider);
    final ctrl = ref.watch(downloadControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Téléchargements')),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (downloads) {
          if (downloads.isEmpty) {
            return const Center(
                child: Text('Aucun téléchargement',
                    style: TextStyle(color: Colors.white54)));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(downloadsListProvider),
            child: ListView.builder(
              itemCount: downloads.length,
              itemBuilder: (context, i) {
                final d = downloads[i];
                final done = d.status == 'done';
                return ListTile(
                  leading: Icon(done
                      ? Icons.play_circle
                      : d.status == 'error'
                          ? Icons.error_outline
                          : Icons.downloading),
                  title: Text(d.title),
                  subtitle: Text(done
                      ? '${(d.bytes / 1048576).toStringAsFixed(1)} Mo · hors-ligne'
                      : d.status),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await ctrl.remove(d.itemKey);
                      ref.invalidate(downloadsListProvider);
                    },
                  ),
                  onTap: done
                      ? () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PlayerScreen(
                                streamUrl: d.filePath, title: d.title),
                          ))
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
