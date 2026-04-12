import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_player_widget.dart';

class AttachmentPreview extends StatefulWidget {
  final Timeline timeline;
  final Event event;
  final Room room;
  final bool isOwn;

  const AttachmentPreview({
    super.key,
    required this.timeline,
    required this.event,
    required this.room,
    required this.isOwn,
  });

  @override
  State<AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<AttachmentPreview> {
  Uri? _uri;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolveUri();
  }

  @override
  void didUpdateWidget(AttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.eventId != widget.event.eventId) {
      _resolveUri();
    }
  }

  void _resolveUri() async {
    try {
      final uri = await widget.event.getAttachmentUri();
      if (mounted) setState(() { _uri = uri; _resolved = true; });
    } catch (_) {
      if (mounted) setState(() { _resolved = true; });
    }
  }

  bool _isImage() => widget.event.attachmentMimetype.startsWith('image/');
  bool _isVideo() => widget.event.attachmentMimetype.startsWith('video/');
  bool _isAudio() {
    final msgtype = widget.event.content['msgtype'];
    return msgtype == 'm.audio' ||
        widget.event.attachmentMimetype.startsWith('audio/') ||
        widget.event.content.containsKey('org.matrix.msc3245.voice');
  }

  String _mediaUrl(Uri uri) {
    final token = widget.room.client.accessToken ?? '';
    if (token.isEmpty) return uri.toString();
    final sep = uri.query.isEmpty ? '?' : '&';
    return '$uri${sep}access_token=$token';
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      final height = _isImage() ? 200.0 : (_isVideo() ? 160.0 : 64.0);
      return Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF0F141B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF263041)),
        ),
        child: const Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    final name = widget.event.getDisplayEvent(widget.timeline).body.trim();
    if (_isImage()) {
      return _ImagePreview(uri: _uri, name: name, mediaUrl: _mediaUrl);
    }
    if (_isVideo()) {
      return _VideoPreview(uri: _uri, name: name, mediaUrl: _mediaUrl);
    }
    if (_isAudio()) {
      final url = _uri == null ? '' : _mediaUrl(_uri!);
      return AudioPlayerWidget(url: url, isOwn: widget.isOwn);
    }
    return _FilePreview(uri: _uri, name: name, mediaUrl: _mediaUrl);
  }
}

// ─── Shared download helper ───────────────────────────────────────────────────

Future<void> _saveAndOpen(
    BuildContext context,
    String url,
    String fileName, {
      bool openAfter = false,
    }) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(
    content: Text('Downloading…'),
    duration: Duration(seconds: 60),
    backgroundColor: Color(0xFF1C2430),
  ));

  try {
    final Directory dir;
    if (Platform.isAndroid || Platform.isIOS) {
      dir = await getTemporaryDirectory();
    } else {
      dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    }

    final safe = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '${dir.path}/$safe';

    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('HTTP ${res.statusCode}');
    }
    final sink = File(path).openWrite();
    await for (final chunk in res) sink.add(chunk);
    await sink.close();
    client.close(force: false);

    messenger.hideCurrentSnackBar();

    if (openAfter) {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        messenger.showSnackBar(SnackBar(
          content: Text('Could not open: ${result.message}'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('Saved: $safe'),
        backgroundColor: const Color(0xFF1C2430),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Open',
          textColor: const Color(0xFF4C8DF6),
          onPressed: () => OpenFilex.open(path),
        ),
      ));
    }
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text('Download failed: $e'),
      backgroundColor: Colors.redAccent,
    ));
  }
}

// ─── In-app fullscreen image viewer ──────────────────────────────────────────

void _openImageViewer(BuildContext context, String url, String name) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, __, ___) => _ImageViewerPage(url: url, name: name),
    transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  ));
}

class _ImageViewerPage extends StatelessWidget {
  final String url;
  final String name;
  const _ImageViewerPage({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Save',
            onPressed: () => _saveAndOpen(context, url, name),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(
                color: Colors.white54,
                strokeWidth: 2,
              ),
            ),
            errorWidget: (_, __, ___) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 64),
                SizedBox(height: 8),
                Text('Could not load image',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Image preview ────────────────────────────────────────────────────────────

class _ImagePreview extends StatelessWidget {
  final Uri? uri;
  final String name;
  final String Function(Uri) mediaUrl;
  const _ImagePreview(
      {required this.uri, required this.name, required this.mediaUrl});

  @override
  Widget build(BuildContext context) {
    if (uri == null) {
      return _shell(
        child: const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white54),
        ),
      );
    }

    final url = mediaUrl(uri!);

    return GestureDetector(
      onTap: () => _openImageViewer(context, url, name),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: 640,
              width: double.infinity,
              height: 200,
              placeholder: (_, __) => _shell(
                child: const Center(
                    child: CircularProgressIndicator.adaptive()),
              ),
              errorWidget: (_, __, ___) => _shell(
                child: const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white54),
                ),
              ),
            ),
            Positioned(
              bottom: 8, left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_out_map,
                        color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text('View',
                        style: TextStyle(
                            color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 8, right: 8,
              child: _CircleBtn(
                icon: Icons.download,
                onTap: () => _saveAndOpen(context, url, name),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shell({required Widget child}) => Container(
    width: double.infinity,
    height: 200,
    decoration: BoxDecoration(
      color: const Color(0xFF0F141B),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF263041)),
    ),
    child: child,
  );
}

// ─── Video preview ────────────────────────────────────────────────────────────

class _VideoPreview extends StatelessWidget {
  final Uri? uri;
  final String name;
  final String Function(Uri) mediaUrl;
  const _VideoPreview(
      {required this.uri, required this.name, required this.mediaUrl});

  @override
  Widget build(BuildContext context) {
    final url = uri == null ? null : mediaUrl(uri!);

    return GestureDetector(
      onTap: url == null
          ? null
          : () => _saveAndOpen(context, url, name, openAfter: true),
      child: Container(
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFF0F141B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF263041)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (url != null)
              Positioned(
                bottom: 10, right: 10,
                child: _CircleBtn(
                  icon: Icons.download,
                  onTap: () => _saveAndOpen(context, url, name),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── File preview ─────────────────────────────────────────────────────────────

class _FilePreview extends StatelessWidget {
  final Uri? uri;
  final String name;
  final String Function(Uri) mediaUrl;
  const _FilePreview(
      {required this.uri, required this.name, required this.mediaUrl});

  @override
  Widget build(BuildContext context) {
    final url = uri == null ? null : mediaUrl(uri!);
    return InkWell(
      onTap: url == null
          ? null
          : () => _saveAndOpen(context, url, name, openAfter: true),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F141B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF263041)),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1E2A38),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.insert_drive_file_outlined,
                color: Color(0xFF4C8DF6), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500
                ),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.download_rounded,
              color: Colors.white54, size: 20),
        ]),
      ),
    );
  }
}

// ─── Shared small button ──────────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
