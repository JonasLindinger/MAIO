import 'package:flutter/material.dart';
import 'package:maio/Widgets/FormattedMessage.dart';
import 'package:matrix/matrix.dart';
import 'AttachmentPreview.dart';

class MessageBubble extends StatelessWidget {
  final Timeline timeline;
  final Event event;
  final Room room;
  final bool isOwn;

  const MessageBubble({
    super.key,
    required this.timeline,
    required this.event,
    required this.room,
    required this.isOwn,
  });

  String? _eventBody(Event event, Timeline timeline) {
    final body = event.getDisplayEvent(timeline).body.trim();
    if (body.isEmpty) return null;

    if (!event.hasAttachment) return body;

    // Only show if it's NOT just a filename
    final mime = event.attachmentMimetype;

    if (mime.startsWith('image/') || mime.startsWith('video/')) {
      // Hide if body looks like a filename
      if (body.contains('.') && body.length < 40) {
        return null;
      }
    }

    return body;
  }

  bool _isFileEvent(Event event) {
    return event.hasAttachment && !_isImageEvent(event) && !_isVideoEvent(event);
  }

  bool _isImageEvent(Event event) {
    return event.hasAttachment && event.attachmentMimetype.startsWith('image/');
  }

  bool _isVideoEvent(Event event) {
    return event.hasAttachment && event.attachmentMimetype.startsWith('video/');
  }

  Future<void> _reactToEvent(Event event, String emoji) async {
    // Hook this up to the reaction API exposed by your matrix version.
    // The UI is ready; this is just the transport hook.
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isOwn ? const Color(0xFF2E7DFF) : const Color(0xFF1C2430);
    final body = _eventBody(event, timeline);

    return GestureDetector(
      onLongPress: () async {
        showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF10151D),
          builder: (context) {
            return SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Text('👍', style: TextStyle(fontSize: 20)),
                    title: const Text(
                      'Like',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _reactToEvent(event, '👍');
                    },
                  ),
                  ListTile(
                    leading: const Text('❤️', style: TextStyle(fontSize: 20)),
                    title: const Text(
                      'Love',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _reactToEvent(event, '❤️');
                    },
                  ),
                  ListTile(
                    leading: const Text('😂', style: TextStyle(fontSize: 20)),
                    title: const Text(
                      'Laugh',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _reactToEvent(event, '😂');
                    },
                  ),
                  ListTile(
                    leading: const Text('🔥', style: TextStyle(fontSize: 20)),
                    title: const Text(
                      'Fire',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _reactToEvent(event, '🔥');
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isOwn ? 18 : 6),
            bottomRight: Radius.circular(isOwn ? 6 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: event.hasAttachment ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AttachmentPreview(
              timeline: timeline,
              room: room,
              event: event,
              isOwn: isOwn,
            ),
            if (body != null && body.isNotEmpty) ...[
              const SizedBox(height: 8),
              FormattedMessage(text: body)
            ],
          ],
        ) : FormattedMessage(text: body ?? ''),
      ),
    );
  }
}
