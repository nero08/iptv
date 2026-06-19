import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../browse/browse_providers.dart';
import '../iptv/models.dart';
import '../sources/source_models.dart';

/// Playback screen backed by `video_player` (ExoPlayer / Media3 on Android).
///
/// ExoPlayer is used because libmpv (media_kit) does not output E-AC-3 (Dolby
/// Digital+) audio on Fire TV — common on this provider's channels — while
/// ExoPlayer decodes it with the device's hardware codec.
///
/// Remote control (live, when a [channels] list is supplied — "zapping"):
///   • Left / Right : previous / next channel
///   • Up           : toggle the channel info / now-next EPG bar
///   • Down         : open the channel list overlay (quick zap)
///   • OK / Enter   : play / pause
///   • MENU         : playback options (stream format, volume)
/// For VOD/series (no channel list) Left/Right seek ∓10s instead.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.isLive = false,
    this.startPositionSecs = 0,
    this.onProgress,
    this.channels,
    this.channelIndex,
    this.source,
  });

  final String streamUrl;
  final String title;
  final bool isLive;
  final int startPositionSecs;

  /// Called periodically with the current position (for resume/history).
  final void Function(Duration position, Duration? duration)? onProgress;

  /// Live channel list + current index + source — enables zapping (prev/next,
  /// info bar, channel list overlay). Null for VOD/series single playback.
  final List<LiveChannel>? channels;
  final int? channelIndex;
  final IptvSource? source;

  bool get canZap =>
      channels != null &&
      channels!.isNotEmpty &&
      channelIndex != null &&
      source != null;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  // Some IPTV servers reject unknown user agents; this one is accepted by the
  // provider (verified) and keeps ExoPlayer's requests consistent with players
  // that work.
  static const Map<String, String> _headers = {
    'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
  };

  VideoPlayerController? _controller;

  late int _index = widget.channelIndex ?? 0;
  late String _title = widget.title;
  String _liveExt = 'ts'; // 'ts' (MPEG-TS) or 'm3u8' (HLS) for live zapping

  bool _showInfo = false; // EPG info bar (Up)
  bool _showList = false; // channel list overlay (Down)
  int _listIndex = 0;
  final ScrollController _listScroll = ScrollController();
  static const double _listItemExtent = 52;

  // Auto-reconnect: a dropped/errored stream relaunches itself with backoff.
  Timer? _retryTimer;
  int _retries = 0;
  bool _reconnecting = false;
  Duration _lastPosition = Duration.zero;
  String? _lastError;

  // Top chrome (title + back arrow) auto-hides after a few seconds and
  // reappears on any remote interaction.
  bool _chromeVisible = true;
  Timer? _chromeTimer;
  static const _chromeTimeout = Duration(seconds: 4);

  double _volume = 1.0;
  bool _isFullscreen = false;
  double? _seekValue; // non-null while dragging seek slider

  bool get _isDesktop => Platform.isLinux || Platform.isWindows;

  LiveChannel? get _current => widget.canZap ? widget.channels![_index] : null;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!_isDesktop) WakelockPlus.enable();
    _open(
      widget.streamUrl,
      startAt: (!widget.isLive && widget.startPositionSecs > 0)
          ? Duration(seconds: widget.startPositionSecs)
          : null,
    );
    _showChrome();
  }

  // --- playback -------------------------------------------------------------

  Future<void> _open(String url, {Duration? startAt}) async {
    final old = _controller;
    old?.removeListener(_onCtrlUpdate);
    // Offline downloads pass a local file path, not a URL — play it as a file
    // (networkUrl would try to fetch the path over HTTP and fail).
    final lower = url.toLowerCase();
    final isNetwork = lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('rtmp') ||
        lower.startsWith('rtsp');
    final options = VideoPlayerOptions(allowBackgroundPlayback: false);
    final c = isNetwork
        ? VideoPlayerController.networkUrl(
            Uri.parse(url),
            httpHeaders: _headers,
            videoPlayerOptions: options,
          )
        : VideoPlayerController.file(
            File(lower.startsWith('file://') ? Uri.parse(url).toFilePath() : url),
            videoPlayerOptions: options,
          );
    _controller = c;
    c.addListener(_onCtrlUpdate);
    if (mounted) setState(() {}); // show loading spinner for the new stream
    unawaited(old?.dispose());
    try {
      await c.initialize();
      if (!mounted || _controller != c) {
        await c.dispose();
        return;
      }
      await c.setVolume(_volume);
      if (startAt != null && startAt > Duration.zero) await c.seekTo(startAt);
      await c.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted && _controller == c) {
        setState(() => _lastError = e.toString());
        _scheduleReconnect();
      }
    }
  }

  void _onCtrlUpdate() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    if (v.isInitialized) {
      _lastPosition = v.position;
      widget.onProgress?.call(v.position, v.duration);
    }
    if (v.hasError) {
      if (mounted) setState(() => _lastError = v.errorDescription ?? 'Flux inaccessible');
      _scheduleReconnect();
      return;
    }
    if (v.isPlaying && _reconnecting && mounted) {
      _retries = 0;
      setState(() { _reconnecting = false; _lastError = null; });
    }
  }

  /// Relaunch the current stream after a backoff (1, 2, 4, 8s, capped).
  void _scheduleReconnect() {
    if (!mounted) return;
    _retryTimer?.cancel();
    final secs = (1 << _retries).clamp(1, 8);
    _retries++;
    if (!_reconnecting) setState(() => _reconnecting = true);
    _retryTimer = Timer(Duration(seconds: secs), () {
      if (!mounted) return;
      final url = widget.canZap
          ? ref
                .read(iptvRepositoryProvider)
                .liveUrl(widget.source!, _current!, ext: _liveExt)
          : widget.streamUrl;
      _open(url, startAt: widget.isLive ? null : _lastPosition);
    });
  }

  // --- zapping --------------------------------------------------------------

  Future<void> _zapBy(int delta) async {
    if (!widget.canZap) return;
    final n = widget.channels!.length;
    await _zapTo(((_index + delta) % n + n) % n);
  }

  Future<void> _zapTo(int idx) async {
    if (!widget.canZap) return;
    final ch = widget.channels![idx];
    final url = ref
        .read(iptvRepositoryProvider)
        .liveUrl(widget.source!, ch, ext: _liveExt);
    setState(() {
      _index = idx;
      _title = ch.name;
      _showList = false;
    });
    await _open(url);
  }

  /// Switch the live stream container (TS <-> HLS) and reopen. No-op for VOD.
  Future<void> _setExt(String ext) async {
    if (!widget.canZap || ext == _liveExt) return;
    setState(() => _liveExt = ext);
    final url = ref
        .read(iptvRepositoryProvider)
        .liveUrl(widget.source!, _current!, ext: ext);
    await _open(url);
  }

  Future<void> _seekBy(int secs) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position + Duration(seconds: secs);
    await c.seekTo(pos < Duration.zero ? Duration.zero : pos);
  }

  Future<void> _setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await _controller?.setVolume(_volume);
    if (mounted) setState(() {});
  }

  Future<void> _toggleFullscreen() async {
    if (!_isDesktop) return;
    final next = !_isFullscreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _isFullscreen = next);
  }

  String _formatDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _moveListSelection(int delta) {
    final n = widget.channels!.length;
    setState(() => _listIndex = ((_listIndex + delta) % n + n) % n);
    _scrollListToSelection();
  }

  void _scrollListToSelection() {
    if (!_listScroll.hasClients) return;
    final target = (_listIndex * _listItemExtent) - 120;
    final max = _listScroll.position.maxScrollExtent;
    _listScroll.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _showChrome() {
    _chromeTimer?.cancel();
    if (!_chromeVisible && mounted) setState(() => _chromeVisible = true);
    _chromeTimer = Timer(_chromeTimeout, () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  void _openOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF15171E),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _OptionsSheet(
        currentExt: _liveExt,
        onSetExt: widget.canZap ? _setExt : null,
        volume: _volume,
        onSetVolume: _setVolume,
        info: _videoInfo(),
      ),
    );
  }

  String _videoInfo() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return '—';
    final s = c.value.size;
    return '${s.width.toInt()}×${s.height.toInt()}';
  }

  // --- key handling ---------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    _showChrome();
    final k = e.logicalKey;
    final isSelect =
        k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.gameButtonA ||
        k == LogicalKeyboardKey.space;

    if (k == LogicalKeyboardKey.contextMenu ||
        k == LogicalKeyboardKey.tvContentsMenu ||
        k == LogicalKeyboardKey.mediaTopMenu) {
      if (_showList) setState(() => _showList = false);
      _openOptions();
      return KeyEventResult.handled;
    }

    if (_showList) {
      if (k == LogicalKeyboardKey.arrowUp) {
        _moveListSelection(-1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        _moveListSelection(1);
        return KeyEventResult.handled;
      }
      if (isSelect) {
        _zapTo(_listIndex);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.escape ||
          k == LogicalKeyboardKey.goBack) {
        setState(() => _showList = false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.arrowLeft) {
      if (widget.canZap) {
        _zapBy(-1);
      } else if (!widget.isLive) {
        _seekBy(-10);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (widget.canZap) {
        _zapBy(1);
      } else if (!widget.isLive) {
        _seekBy(10);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && widget.canZap) {
      setState(() => _showInfo = !_showInfo);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown && widget.canZap) {
      setState(() {
        _showList = true;
        _listIndex = _index;
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollListToSelection(),
      );
      return KeyEventResult.handled;
    }
    if (isSelect) {
      final c = _controller;
      if (c != null && c.value.isInitialized) {
        c.value.isPlaying ? c.pause() : c.play();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    if (!_isDesktop) WakelockPlus.disable();
    if (_isDesktop && _isFullscreen) windowManager.setFullScreen(false);
    _retryTimer?.cancel();
    _chromeTimer?.cancel();
    _listScroll.dispose();
    _controller?.removeListener(_onCtrlUpdate);
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    Widget body = SafeArea(
      child: Stack(
        children: [
          Center(
            child: ready
                ? AspectRatio(
                    aspectRatio: c.value.aspectRatio <= 0
                        ? 16 / 9
                        : c.value.aspectRatio,
                    child: VideoPlayer(c),
                  )
                : const CircularProgressIndicator(),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const BackButton(color: Colors.white),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 56,
            right: 16,
            child: AnimatedOpacity(
              opacity: _chromeVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                _title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
          ),
          if (_showInfo && _current != null)
            Positioned(left: 0, right: 0, bottom: 0, child: _infoBar()),
          if (_showList && widget.canZap)
            Positioned(top: 0, bottom: 0, right: 0, child: _channelList()),
          if (_reconnecting)
            Center(child: _ReconnectingBadge(error: _lastError, retries: _retries)),
          if (_isDesktop)
            Positioned(left: 0, right: 0, bottom: 0, child: _desktopControls()),
        ],
      ),
    );
    if (_isDesktop) {
      body = MouseRegion(
        onHover: (_) => _showChrome(),
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _setVolume(_volume - e.scrollDelta.dy / 1000);
            }
          },
          child: body,
        ),
      );
    }
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: body,
      ),
    );
  }

  // --- overlays -------------------------------------------------------------

  Widget _infoBar() {
    final ch = _current!;
    final nn = ch.streamId > 0
        ? ref.watch(nowNextProvider(ch.streamId)).valueOrNull
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ch.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          if (nn?.now?.title != null)
            Text(
              'En cours : ${nn!.now!.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          if (nn?.next?.title != null)
            Text(
              'À suivre : ${nn!.next!.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
          if (nn?.now?.title == null && nn?.next?.title == null)
            const Text(
              'EPG indisponible',
              style: TextStyle(color: Colors.white54),
            ),
        ],
      ),
    );
  }

  Widget _desktopControls() {
    final c = _controller;
    return IgnorePointer(
      ignoring: !_chromeVisible,
      child: AnimatedOpacity(
        opacity: _chromeVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
          child: c == null
              ? _buildBottomRow(null, false)
              : ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: c,
                  builder: (context, value, _) {
                    final ready = value.isInitialized;
                    final isVod = !widget.isLive && ready;
                    final position = value.position;
                    final duration = value.duration;
                    final ms = duration.inMilliseconds;
                    final sliderVal = _seekValue ??
                        (ms > 0
                            ? (position.inMilliseconds / ms).clamp(0.0, 1.0)
                            : 0.0);
                    final displayPos = _seekValue != null && ms > 0
                        ? Duration(milliseconds: (_seekValue! * ms).round())
                        : position;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isVod)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                Text(
                                  _formatDur(displayPos),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: sliderVal,
                                    onChanged: ms > 0
                                        ? (v) => setState(() => _seekValue = v)
                                        : null,
                                    onChangeEnd: ms > 0
                                        ? (v) {
                                            c.seekTo(Duration(
                                                milliseconds: (v * ms).round()));
                                            setState(() => _seekValue = null);
                                          }
                                        : null,
                                    activeColor: Colors.white,
                                    inactiveColor: Colors.white30,
                                  ),
                                ),
                                Text(
                                  _formatDur(duration),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        _buildBottomRow(ready ? c : null, value.isPlaying),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildBottomRow(VideoPlayerController? c, bool isPlaying) {
    return Row(
      children: [
        IconButton(
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
          onPressed: c == null ? null : () => isPlaying ? c.pause() : c.play(),
        ),
        const SizedBox(width: 4),
        Icon(
          _volume == 0
              ? Icons.volume_off
              : _volume < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
          color: Colors.white70,
          size: 20,
        ),
        SizedBox(
          width: 120,
          child: Slider(
            value: _volume,
            onChanged: _setVolume,
            activeColor: Colors.white,
            inactiveColor: Colors.white30,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(
            _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            color: Colors.white,
          ),
          tooltip: _isFullscreen ? 'Quitter plein écran (F11)' : 'Plein écran (F11)',
          onPressed: _toggleFullscreen,
        ),
      ],
    );
  }

  Widget _channelList() {
    final channels = widget.channels!;
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      width: 340,
      color: Colors.black.withValues(alpha: 0.85),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Chaînes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _listScroll,
              itemExtent: _listItemExtent,
              itemCount: channels.length,
              itemBuilder: (context, i) {
                final selected = i == _listIndex;
                final playing = i == _index;
                return Container(
                  color: selected ? accent.withValues(alpha: 0.35) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(
                        playing ? Icons.play_arrow : Icons.live_tv,
                        size: 18,
                        color: playing ? accent : Colors.white70,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          channels[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Playback options popup (remote MENU): stream format + volume.
class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({
    required this.currentExt,
    required this.onSetExt,
    required this.volume,
    required this.onSetVolume,
    required this.info,
  });
  final String currentExt;
  final void Function(String ext)? onSetExt; // null for VOD/series
  final double volume;
  final Future<void> Function(double) onSetVolume;
  final String info;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late String _ext = widget.currentExt;
  late double _vol = widget.volume;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onSetExt != null) ...[
            _heading('Format du flux (essayer si problème)'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'ts', label: Text('TS (défaut)')),
                  ButtonSegment(value: 'm3u8', label: Text('HLS')),
                ],
                selected: {_ext},
                onSelectionChanged: (s) {
                  setState(() => _ext = s.first);
                  widget.onSetExt!(s.first);
                },
              ),
            ),
            const Divider(height: 1),
          ],
          _heading('Volume'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.volume_down, color: Colors.white),
                  onPressed: () => _setVol(_vol - 0.1),
                ),
                Expanded(
                  child: Text(
                    '${(_vol * 100).round()} %',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up, color: Colors.white),
                  onPressed: () => _setVol(_vol + 0.1),
                ),
                TextButton(
                  onPressed: () => _setVol(1.0),
                  child: const Text('100%'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _heading('Vidéo'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Résolution : ${widget.info}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _setVol(double v) {
    final nv = v.clamp(0.0, 1.0);
    setState(() => _vol = nv);
    widget.onSetVolume(nv);
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

/// Centered overlay shown while a dropped stream is reconnecting.
/// Displays a spinner, "Try to connect..." label, optional error detail,
/// and the current retry attempt count.
class _ReconnectingBadge extends StatelessWidget {
  const _ReconnectingBadge({this.error, required this.retries});

  final String? error;
  final int retries;

  @override
  Widget build(BuildContext context) {
    // Shorten extremely long platform error strings so they fit on screen.
    String? shortError = error;
    if (shortError != null && shortError.length > 120) {
      shortError = '${shortError.substring(0, 120)}...';
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                retries == 0
                    ? 'Try to connect...'
                    : 'Try to connect... (attempt $retries)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (shortError != null) ...[
            const SizedBox(height: 10),
            Text(
              shortError,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
