import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class AttachmentPreview extends StatelessWidget {
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

  bool _isImage() => event.attachmentMimetype.startsWith('image/');
  bool _isVideo() => event.attachmentMimetype.startsWith('video/');

  String _mediaUrl(Uri uri) {
    final token = room.client.accessToken ?? '';
    if (token.isEmpty) return uri.toString();
    final sep = uri.query.isEmpty ? '?' : '&';
    return '$uri${sep}access_token=$token';
  }

  @override
  Widget build(BuildContext context) {
    final name = event.getDisplayEvent(timeline).body.trim();

    if (_isImage()) return _ImagePreview(event: event, name: name, mediaUrl: _mediaUrl);
    if (_isVideo()) return _VideoPreview(event: event, name: name, mediaUrl: _mediaUrl, context: context);

    return _FilePreview(
      event: event,
      name: name,
      mediaUrl: _mediaUrl,
      timeline: timeline,
      context: context,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image
// ─────────────────────────────────────────────────────────────────────────────

class _ImagePreview extends StatelessWidget {
  final Event event;
  final String name;
  final String Function(Uri) mediaUrl;

  const _ImagePreview({
    required this.event,
    required this.name,
    required this.mediaUrl,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uri?>(
      future: event.getAttachmentUri(),
      builder: (context, snap) {
        final uri = snap.data;
        if (uri == null) {
          return _placeholder(const Icon(Icons.broken_image_outlined,
              color: Colors.white70));
        }

        final url = mediaUrl(uri);

        return GestureDetector(
          onTap: () => _showFullscreen(context, url, name),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  memCacheWidth: 640,
                  width: double.infinity,
                  placeholder: (_, __) => _placeholder(
                    const CircularProgressIndicator.adaptive(),
                  ),
                  errorWidget: (_, __, ___) => _placeholder(
                    const Icon(Icons.broken_image_outlined,
                        color: Colors.white70),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: _DownloadButton(
                  onTap: () => _downloadMedia(context, uri, name),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _placeholder(Widget child) => Container(
    width: double.infinity,
    height: 180,
    decoration: BoxDecoration(
      color: const Color(0xFF0F141B),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF263041)),
    ),
    child: Center(child: child),
  );

  void _showFullscreen(BuildContext context, String url, String name) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.95),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorWidget: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 64),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: const Color(0xAA000000),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadMedia(
      BuildContext context, Uri uri, String fileName) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final savePath = await FilePicker.platform
          .saveFile(dialogTitle: 'Save as', fileName: fileName);
      if (savePath == null) return;
      await _downloadWithProgress(uri, savePath);
      messenger.showSnackBar(SnackBar(
        content: Text('Saved to $savePath'),
        backgroundColor: const Color(0xFF1C2430),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Download failed: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _downloadWithProgress(Uri uri, String path) async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(mediaUrl(uri)));
    final res = await req.close();
    final sink = File(path).openWrite();
    await for (final chunk in res) {
      sink.add(chunk);
    }
    await sink.close();
    client.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video
// ─────────────────────────────────────────────────────────────────────────────

class _VideoPreview extends StatelessWidget {
  final Event event;
  final String name;
  final String Function(Uri) mediaUrl;
  final BuildContext context;

  const _VideoPreview({
    required this.event,
    required this.name,
    required this.mediaUrl,
    required this.context,
  });

  @override
  Widget build(BuildContext ctx) {
    return FutureBuilder<Uri?>(
      future: event.getAttachmentUri(),
      builder: (ctx, snap) {
        final uri = snap.data;
        return GestureDetector(
          onTap: uri == null ? null : () => _showVideo(ctx, uri),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 180),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F141B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Icon(Icons.play_circle_fill,
                      size: 64, color: Colors.white70),
                ),
              ),
              if (uri != null)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: _DownloadButton(
                    onTap: () => _downloadVideo(ctx, uri),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showVideo(BuildContext context, Uri uri) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.95),
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0B0F14),
        insetPadding: const EdgeInsets.all(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_fill,
                  size: 88, color: Colors.white70),
              const SizedBox(height: 16),
              const Text('Video attachment',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Open the media URL in a browser/player to watch it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF98A2B3))),
              const SizedBox(height: 12),
              SelectableText(mediaUrl(uri),
                  style:
                  const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadVideo(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final savePath = await FilePicker.platform
          .saveFile(dialogTitle: 'Save video as', fileName: name);
      if (savePath == null) return;
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(mediaUrl(uri)));
      final res = await req.close();
      final sink = File(savePath).openWrite();
      await for (final chunk in res) sink.add(chunk);
      await sink.close();
      client.close();
      messenger.showSnackBar(SnackBar(
          content: Text('Saved to $savePath'),
          backgroundColor: const Color(0xFF1C2430)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// File / generic
// ─────────────────────────────────────────────────────────────────────────────

class _FilePreview extends StatelessWidget {
  final Event event;
  final String name;
  final String Function(Uri) mediaUrl;
  final Timeline timeline;
  final BuildContext context;

  const _FilePreview({
    required this.event,
    required this.name,
    required this.mediaUrl,
    required this.timeline,
    required this.context,
  });

  @override
  Widget build(BuildContext ctx) {
    return FutureBuilder<Uri?>(
      future: event.getAttachmentUri(),
      builder: (ctx, snap) {
        final uri = snap.data;
        return InkWell(
          onTap: uri == null ? null : () => _open(ctx, uri),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F141B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF263041)),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.download_rounded, color: Colors.white70),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save attachment as', fileName: name);
      if (savePath == null) return;
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(mediaUrl(uri)));
      final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('HTTP ${res.statusCode}', uri: uri);
      }
      final bytes = await res.fold<List<int>>(
          [], (buf, chunk) => buf..addAll(chunk));
      await File(savePath).writeAsBytes(bytes, flush: true);
      client.close();
      messenger.showSnackBar(SnackBar(
          content: Text('Saved to $savePath'),
          backgroundColor: const Color(0xFF1C2430)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent));
    }8
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DownloadButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DownloadButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        icon: const Icon(Icons.download, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}