import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Generic media tile reused by Live (logos), VOD and Series (posters).
///
/// Focusable for D-pad / remote navigation on Android TV: the whole tile is an
/// [InkWell], so it receives focus, shows a highlight border, and fires [onTap]
/// on the remote's OK/select button. The enclosing grid auto-scrolls to keep
/// the focused tile visible. [onLongPress] is wired to the favorite toggle on
/// screens that support it, so the star can be toggled without a touchscreen.
class MediaTile extends StatefulWidget {
  const MediaTile({
    super.key,
    required this.title,
    this.imageUrl,
    this.subtitle,
    this.aspectRatio = 2 / 3,
    this.onTap,
    this.onLongPress,
    this.icon = Icons.live_tv,
    this.trailing,
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final double aspectRatio;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final IconData icon;
  final Widget? trailing;

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // InkWell makes the whole tile a single focusable, remote-activatable
    // target (D-pad OK / gamepad A fire onTap). We draw our own focus border
    // instead of the default ink highlight so it reads clearly on TV.
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      borderRadius: BorderRadius.circular(10),
      focusColor: Colors.transparent,
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _focused ? accent : Colors.transparent,
            width: 3,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: widget.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: widget.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _ph(),
                          errorWidget: (_, __, ___) => _ph(),
                        )
                      else
                        _ph(),
                      if (widget.trailing != null)
                        Positioned(top: 4, right: 4, child: widget.trailing!),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            if (widget.subtitle != null)
              Text(widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }

  Widget _ph() => Container(
        color: const Color(0xFF23262E),
        child: Icon(widget.icon, color: Colors.white24, size: 36),
      );
}
