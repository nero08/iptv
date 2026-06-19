import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'profile_controller.dart';

/// Manage watch profiles: list, switch active, create, rename, delete.
class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profils')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: profilesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (profiles) => ListView(
          children: [
            for (final p in profiles)
              RadioListTile<String>(
                value: p.id,
                groupValue: activeId ?? profiles.first.id,
                title: Text(p.name),
                secondary: profiles.length > 1
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await ref.read(profileControllerProvider).delete(p.id);
                          ref.invalidate(profilesProvider);
                          if (activeId == p.id) {
                            ref.read(activeProfileIdProvider.notifier).state = null;
                          }
                        },
                      )
                    : null,
                onChanged: (v) =>
                    ref.read(activeProfileIdProvider.notifier).state = v,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveau profil'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nom du profil'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Créer')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(profileControllerProvider).create(name);
      ref.invalidate(profilesProvider);
    }
  }
}
