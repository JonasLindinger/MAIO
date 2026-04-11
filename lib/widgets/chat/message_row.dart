import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'avatar.dart';
import 'message_bubble.dart';

class MessageRow extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final Room room;
  final bool isOwn;
  final Future<String?> Function(Event) resolveAvatarUrl;
  final Function onReacted;
  final Function(Event)? onReply;

  const MessageRow({
    super.key,
    required this.event,
    required this.timeline,
    required this.room,
    required this.isOwn,
    required this.resolveAvatarUrl,
    required this.onReacted,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    // NOTE: RepaintBoundary has been intentionally removed here.
    // It prevented MessageBubble (a StatefulWidget) from repainting when its
    // internal state changed (reactions, drag offset), causing the UI to appear
    // stale until the whole page rebuilt.
    final bubble = MessageBubble(
      timeline: timeline,
      event: event,
      room: room,
      isOwn: isOwn,
      onReacted: onReacted,
      // Fix: was missing — this is why swipe-to-reply never fired.
      onReply: onReply,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
        isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOwn) ...[
            AvatarWidget(event: event, resolveAvatarUrl: resolveAvatarUrl),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
              isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isOwn)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      event.senderFromMemoryOrFallback.calcDisplayname(),
                      style: const TextStyle(
                        color: Color(0xFF9AA4B2),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                event.status.isSent
                    ? bubble
                    : Opacity(opacity: 0.55, child: bubble),
              ],
            ),
          ),
        ],
      ),
    );
  }
}