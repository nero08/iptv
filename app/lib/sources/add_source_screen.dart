import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../iptv/m3u_parser.dart';
import '../iptv/xtream_client.dart';
import 'source_models.dart';
import 'source_repository.dart';

/// "Ajouter une source" — BYO entry for an Xtream portal or an M3U URL.
/// Validates connectivity before saving (Xtream: fetchSourceInfo; M3U: a
/// successful download+parse of at least one channel).
class AddSourceScreen extends ConsumerStatefulWidget {
  const AddSourceScreen({super.key});

  @override
  ConsumerState<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends ConsumerState<AddSourceScreen> {
  SourceKind _kind = SourceKind.xtream;
  final _name = TextEditingController(text: 'Ma source');
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _m3u = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _server, _user, _pass, _m3u]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isXtream = _kind == SourceKind.xtream;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter une source')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<SourceKind>(
            segments: const [
              ButtonSegment(value: SourceKind.xtream, label: Text('Xtream')),
              ButtonSegment(value: SourceKind.m3u, label: Text('M3U')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          if (isXtream) ...[
            TextField(
              key: const Key('serverField'),
              controller: _server,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Serveur (http://host:port)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                  labelText: 'Utilisateur', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              // Xtream password is a credential -> mask it like the M3U field.
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Mot de passe', border: OutlineInputBorder()),
            ),
          ] else
            TextField(
              key: const Key('m3uField'),
              controller: _m3u,
              // M3U URLs can embed credentials -> obscure the field.
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'URL M3U', border: OutlineInputBorder()),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Valider et enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(sourceRepositoryProvider);
    try {
      if (_kind == SourceKind.xtream) {
        final server = _server.text.trim();
        if (server.isEmpty || _user.text.trim().isEmpty || _pass.text.trim().isEmpty) {
          throw 'Renseignez serveur, utilisateur et mot de passe.';
        }
        // Validate connectivity before persisting.
        final client = XtreamClient(
            serverUrl: server, username: _user.text.trim(), password: _pass.text.trim());
        final info = await client.fetchSourceInfo();
        if (!info.isActive) {
          throw 'Compte du portail inactif ou expiré.';
        }
        await repo.addLocalXtream(
          name: _name.text.trim(),
          serverUrl: server,
          username: _user.text.trim(),
          password: _pass.text.trim(),
        );
      } else {
        final url = _m3u.text.trim();
        if (url.isEmpty) throw 'Renseignez l\'URL M3U.';
        // Validate by downloading + parsing.
        final res = await Dio().get<List<int>>(url,
            options: Options(responseType: ResponseType.bytes));
        final channels = M3uParser.parse(
            M3uParser.decodeBytes(Uint8List.fromList(res.data ?? const <int>[])));
        if (channels.isEmpty) throw 'Aucune chaîne trouvée dans cette playlist.';
        await repo.addLocalM3u(name: _name.text.trim(), m3uUrl: url);
      }
      ref.invalidate(sourceListProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = _humanize(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _humanize(Object e) {
    if (e is String) return e;
    if (e is DioException) return 'Connexion impossible au serveur.';
    return 'Échec de la validation : $e';
  }
}
