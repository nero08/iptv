import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../favorites/favorites_screen.dart';
import '../profiles/profiles_screen.dart';
import '../sources/source_list_screen.dart';
import '../downloads/downloads_screen.dart';

/// Settings: device usage (count/max), profile + source + downloads entry
/// points, multi-screen awareness note, and logout (clears the code, keeps the
/// device_id so re-login does not consume an extra device slot).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final count = auth.deviceCount;
    final max = auth.maxDevices;
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        children: [
          const _SectionHeader('Cet appareil'),
          ListTile(
            leading: const Icon(Icons.devices),
            title: const Text('Appareils utilisés'),
            subtitle: Text((count != null && max != null)
                ? '$count / $max appareils sur ce compte'
                : 'Inconnu'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'La gestion des appareils (suppression, blocage) se fait depuis '
              'l\'administration. Si la limite est atteinte, libérez un appareil '
              'côté admin.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const Divider(),
          const _SectionHeader('Bibliothèque'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Profils'),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfilesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.star_border),
            title: const Text('Favoris'),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FavoritesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Sources IPTV'),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SourceListScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Téléchargements'),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadsScreen())),
          ),
          const Divider(),
          const _SectionHeader('Compte'),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Déconnexion',
                style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              ref.read(authControllerProvider.notifier).logout();
              // Pop Settings (and any pushed routes) so the root AuthGate's
              // login screen becomes visible — logout must close the menu.
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      );
}
