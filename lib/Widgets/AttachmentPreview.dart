import 'dart:io';
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
    required this.isOwn
  });

  bool _isImageEvent(Event event) {
    return event.hasAttachment && event.attachmentMimetype.startsWith('image/');
  }

  bool _isVideoEvent(Event event) {
    return event.hasAttachment && event.attachmentMimetype.startsWith('video/');
  }

  bool _isFileEvent(Event event) {
    return event.hasAttachment && !_isImageEvent(event) && !_isVideoEvent(event);
  }

  @override
  Widget build(BuildContext context) {
    final isImage = _isImageEvent(event);
    final isVideo = _isVideoEvent(event);
    final isFile = _isFileEvent(event);
    final String name = event.getDisplayEvent(timeline).body.trim();

    if (isImage) {
      return FutureBuilder<Uri?>(
        future: event.getAttachmentUri(),
        builder: (context, snapshot) {
          final uri = snapshot.data;
          if (uri == null) {
            return Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: const Color(0xFF0F141B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF263041)),
              ),
              child: const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white70,
                ),
              ),
            );
          }

          return GestureDetector(
            onTap: () => _openFullscreenImage(context, uri),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: const Color(0xFF0F141B),
                constraints: const BoxConstraints(
                  maxWidth: 320,
                  maxHeight: 260,
                  minHeight: 96,
                  minWidth: 96,
                ),
                child: Image.network(
                  _mediaUrlWithAccessToken(uri),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('image load error: $error');
                    return Container(
                      height: 180,
                      color: const Color(0xFF0F141B),
                      child: const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    }

    if (isVideo) {
      return FutureBuilder<Uri?>(
        future: event.getAttachmentUri(),
        builder: (context, snapshot) {
          final uri = snapshot.data;

          return GestureDetector(
            onTap: uri == null ? null : () => _openFullscreenVideo(context, uri),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 180),
              decoration: BoxDecoration(
                color: const Color(0xFF0F141B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF263041)),
              ),
              child: const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  size: 64,
                  color: Colors.white70,
                ),
              ),
            ),
          );
        },
      );
    }

    if (isFile) {
      return FutureBuilder<Uri?>(
        future: event.getAttachmentUri(),
        builder: (context, snapshot) {
          final uri = snapshot.data;

          return InkWell(
            onTap: uri == null ? null : () => _openAttachment(context, uri),
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
                        fontWeight: FontWeight.w500,
                      ),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F141B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF263041)),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'File',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFullscreenImage(BuildContext context, Uri uri) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.95),
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      _mediaUrlWithAccessToken(uri),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 64,
                        );
                      },
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
        );
      },
    );
  }

  String _mediaUrlWithAccessToken(Uri uri) {
    final token = room.client.accessToken ?? '';
    if (token.isEmpty) return uri.toString();

    final separator = uri.query.isEmpty ? '?' : '&';
    return '${uri.toString()}${separator}access_token=$token';
  }

  Future<void> _openFullscreenVideo(BuildContext context, Uri uri) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.95),
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: const Color(0xFF0B0F14),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_circle_fill,
                  size: 88,
                  color: Colors.white70,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Video attachment',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Open the media URL in a browser/player to watch it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF98A2B3)),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  _mediaUrlWithAccessToken(uri),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
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
        );
      },
    );
  }

  Future<void> _openAttachment(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final suggestedName = event.getDisplayEvent(timeline).body.trim();
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save attachment as',
        fileName: suggestedName,
      );

      if (savePath == null) return;

      final bytes = await _downloadAttachmentBytes(uri);
      final file = File(savePath);
      await file.writeAsBytes(bytes, flush: true);

      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved to $savePath'),
          backgroundColor: const Color(0xFF1C2430),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<List<int>> _downloadAttachmentBytes(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_mediaUrlWithAccessToken(uri)));
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Failed to download attachment (${response.statusCode})',
          uri: uri,
        );
      }

      return await response.fold<List<int>>(
        <int>[],
            (buffer, chunk) => buffer..addAll(chunk),
      );
    } finally {
      client.close(force: true);
    }
  }
}
