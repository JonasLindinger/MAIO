import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String url;
  final bool isOwn;

  const AudioPlayerWidget({
    super.key,
    required this.url,
    required this.isOwn,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late final Player _player;

  bool _isLoaded = false;
  String? _error;

  // Mirrored player state, updated via stream subscriptions.
  bool _playing = false;
  bool _completed = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    _player = Player();
    _subscribeTo(_player);
    _init();
  }

  void _subscribeTo(Player p) {
    void upd(void Function() fn) {
      if (mounted) setState(fn);
    }

    _subs.addAll([
      p.stream.playing.listen((v) => upd(() => _playing = v)),
      p.stream.completed.listen((v) => upd(() => _completed = v)),
      p.stream.buffering.listen((v) => upd(() => _buffering = v)),
      p.stream.position.listen((v) => upd(() => _position = v)),
      p.stream.duration.listen((v) => upd(() => _duration = v)),
    ]);
    // Intentionally NOT subscribing to p.stream.log — the default
    // just_audio_media_kit handler prints every MPV log event to the console.
  }

  Future<void> _init() async {
    if (widget.url.isEmpty) {
      if (mounted) setState(() => _error = 'No audio URL');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();

      // Derive a stable cache filename from the URL's path (Matrix media ID).
      final parsed = Uri.parse(widget.url);
      final segments = parsed.pathSegments.where((s) => s.isNotEmpty).toList();
      final id = segments.isNotEmpty
          ? segments.last
          : DateTime.now().millisecondsSinceEpoch.toString();
      final safeName = id.replaceAll(RegExp(r'[^\w\-]'), '_');
      final file = File('${dir.path}/maio_audio_$safeName');

      if (!await file.exists()) {
        debugPrint('AudioPlayerWidget: downloading $id');
        final httpClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 20);
        try {
          final req = await httpClient.getUrl(parsed);
          final res = await req.close();
          if (res.statusCode < 200 || res.statusCode >= 300) {
            throw HttpException('HTTP ${res.statusCode}');
          }
          final sink = file.openWrite();
          await for (final chunk in res) sink.add(chunk);
          await sink.close();
        } catch (_) {
          await file.delete().catchError((_) => file);
          rethrow;
        } finally {
          httpClient.close(force: false);
        }
      }

      // play: false — only preload, don't auto-play.
      await _player.open(Media(file.uri.toString()), play: false);
      if (mounted) setState(() => _isLoaded = true);
      debugPrint('AudioPlayerWidget: loaded ${file.path}');
    } catch (e) {
      debugPrint('AudioPlayerWidget: error: $e');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _replay() async {
    // Immediately clear the completed flag so the UI shows the pause button
    // without waiting for the stream event.
    if (mounted) setState(() => _completed = false);
    await _player.seek(Duration.zero);
    await _player.play();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isOwn ? Colors.white : const Color(0xFF4C8DF6);

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // ── Determine button state ────────────────────────────────────────────────
    Widget button;
    if (!_isLoaded || _buffering) {
      button = Container(
        margin: const EdgeInsets.all(8),
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    } else if (_completed) {
      button = IconButton(
        icon: const Icon(Icons.replay_rounded),
        color: color,
        onPressed: _replay,
      );
    } else if (_playing) {
      button = IconButton(
        icon: const Icon(Icons.pause_rounded),
        color: color,
        onPressed: _player.pause,
      );
    } else {
      button = IconButton(
        icon: const Icon(Icons.play_arrow_rounded),
        color: color,
        onPressed: _player.play,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          button,
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: color,
                    inactiveTrackColor: color.withOpacity(0.3),
                    thumbColor: color,
                  ),
                  child: Slider(
                    value: _position.inMilliseconds
                        .toDouble()
                        .clamp(0, _duration.inMilliseconds.toDouble()),
                    max: _duration.inMilliseconds
                        .toDouble()
                        .clamp(0.01, double.infinity),
                    onChanged: _isLoaded
                        ? (v) =>
                            _player.seek(Duration(milliseconds: v.toInt()))
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(_position),
                          style: TextStyle(
                              color: color.withOpacity(0.7), fontSize: 10)),
                      Text(_fmt(_duration),
                          style: TextStyle(
                              color: color.withOpacity(0.7), fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
