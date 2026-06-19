import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import 'auth_controller.dart';
import 'auth_state.dart';

/// The only authentication UI: enter an 8-char access code.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _controller = TextEditingController();
  String _code = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _errorText(AuthState s) {
    if (s.status != AuthStatus.error) return null;
    switch (s.errorCode) {
      case 'INVALID_CODE':
        return 'Code invalide';
      case 'NETWORK':
        return 'Connexion impossible. Reessayez.';
      default:
        final detail = s.errorDetail != null ? '\n${s.errorDetail}' : '';
        return 'Erreur [${s.errorCode}]$detail';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final canSubmit = _code.length == AppConfig.codeLength && !state.busy;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_circle_fill, size: 72, color: Color(0xFF7C4DFF)),
                const SizedBox(height: 16),
                Text('Deko IPTV',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Entrez votre code d\'accès',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 28),
                TextField(
                  key: const Key('codeField'),
                  controller: _controller,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: AppConfig.codeLength,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 28,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold),
                  inputFormatters: [
                    UpperCaseFormatter(),
                    FilteringTextInputFormatter.allow(
                        RegExp('[${AppConfig.codeAlphabet}]')),
                    LengthLimitingTextInputFormatter(AppConfig.codeLength),
                  ],
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    counterText: '',
                    errorText: _errorText(state),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _code = v),
                  onSubmitted: (_) {
                    if (canSubmit) _submit();
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('submitButton'),
                    onPressed: canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: state.busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Se connecter'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('createCodeButton'),
                  onPressed: state.busy ? null : _showCreateDialog,
                  child: const Text('Pas de code ? Créer un accès'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    ref.read(authControllerProvider.notifier).redeem(_code);
  }

  /// Self-service flow: ask for a profile name -> create a code -> show it so
  /// the user notes it -> log in with it.
  Future<void> _showCreateDialog() async {
    FocusScope.of(context).unfocus();
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Créer un accès'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Votre nom / profil',
            hintText: 'Ex : Jean Dupont',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(nameController.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty || !mounted) return;

    final code = await ref.read(authControllerProvider.notifier).createCode(name);
    if (!mounted) return;
    if (code == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Création impossible. Réessayez.')));
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Votre code d\'accès'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              code,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 30,
                  letterSpacing: 6,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Notez ce code : il vous servira à vous reconnecter sur cet '
              'appareil ou un autre.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    ref.read(authControllerProvider.notifier).redeem(code);
  }
}

/// Uppercases input as it is typed (codes are uppercase alphanumeric).
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
