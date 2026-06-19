import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../iptv/models.dart';
import '../player/player_screen.dart';
import 'browse_providers.dart';

/// Series detail: poster/plot + season selector + episode list -> player.
class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({super.key, required this.item});
  final SeriesItem item;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  int _seasonIndex = 0;

  @override
  Widget build(BuildContext context) {
    final infoAsync = ref.watch(seriesInfoProvider(widget.item.seriesId));
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.name)),
      body: infoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur: $e')),
        data: (info) {
          if (info.seasons.isEmpty) {
            return const Center(child: Text('Aucun épisode disponible'));
          }
          final idx = _seasonIndex.clamp(0, info.seasons.length - 1);
          final season = info.seasons[idx];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(info),
              const SizedBox(height: 16),
              if (info.seasons.length > 1) _seasonSelector(info),
              const SizedBox(height: 8),
              ...season.episodes.map((e) => _episodeTile(info, e)),
            ],
          );
        },
      ),
    );
  }

  Widget _header(SeriesInfo info) {
    final poster = info.cover ?? widget.item.cover;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 110,
            height: 165,
            child: (poster != null && poster.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: poster,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _ph(),
                    placeholder: (_, __) => _ph(),
                  )
                : _ph(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.item.name,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (info.genre != null)
                Text('Genre : ${info.genre}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              if (info.plot != null) ...[
                const SizedBox(height: 8),
                Text(info.plot!,
                    maxLines: 6, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _seasonSelector(SeriesInfo info) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: info.seasons.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == _seasonIndex;
          return ChoiceChip(
            label: Text('Saison ${info.seasons[i].number}'),
            selected: selected,
            onSelected: (_) => setState(() => _seasonIndex = i),
          );
        },
      ),
    );
  }

  Widget _episodeTile(SeriesInfo info, Episode e) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.play_circle_outline),
      title: Text(e.episodeNum != null ? '${e.episodeNum}. ${e.title}' : e.title),
      subtitle: e.durationSecs != null
          ? Text('${(e.durationSecs! / 60).round()} min')
          : null,
      onTap: () {
        final source = ref.read(activeSourceProvider)!;
        final url = ref
            .read(iptvRepositoryProvider)
            .episodeUrl(source, e.id, e.containerExtension);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlayerScreen(streamUrl: url, title: e.title),
        ));
      },
    );
  }

  Widget _ph() => Container(
      color: const Color(0xFF23262E),
      child: const Icon(Icons.video_library, color: Colors.white24, size: 32));
}
