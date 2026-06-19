import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'auth_state.dart';

/// Terminal-state screen for device-limit / blocked / expired accounts.
/// Reached when [AuthState] is one of those statuses. Offers a way back to the
/// login screen (logout clears the stored code).
class DeviceLimitScreen extends ConsumerWidget {
  const DeviceLimitScreen({super.key, required this.status});

  final AuthStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, title, message) = _content(status);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 64, color: Colors.orangeAccent),
                const SizedBox(height: 16),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 28),
                OutlinedButton(
                  key: const Key('backToLoginButton'),
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                  child: const Text('Retour à la connexion'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (IconData, String, String) _content(AuthStatus s) {
    switch (s) {
      case AuthStatus.deviceLimit:
        return (
          Icons.devices_other,
          'Limite d\'appareils atteinte',
          'Ce code est déjà utilisé sur le nombre maximum d\'appareils. '
              'Gérez vos appareils depuis l\'administration.'
        );
      case AuthStatus.blocked:
        return (
          Icons.block,
          'Compte bloqué',
          'Ce compte a été bloqué. Contactez votre administrateur.'
        );
      case AuthStatus.expired:
        return (
          Icons.timer_off,
          'Compte expiré',
          'Ce compte a expiré. Contactez votre administrateur pour le renouveler.'
        );
      default:
        return (Icons.error, 'Erreur', 'Une erreur est survenue.');
    }
  }
}
