import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'avatar.dart';
import 'message_bubble.dart';

class MessageRow extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  final Room room;
  final bool isOwn;
  final Future<String?> Function(Event) resolveAvatarUrl;
  final Function onReacted;
  final Function(Event)? onReply;
  final void Function(String eventId)? onScrollToEvent;

  const MessageRow({
    super.key,
    required this.event,
    required this.timeline,
    required this.room,
    required this.isOwn,
    required this.resolveAvatarUrl,
    required this.onReacted,
    this.onReply,
    this.onScrollToEvent,
  });

  @override
  MessageRowState createState() => MessageRowState();
}

class MessageRowState extends State<MessageRow> {
  final GlobalKey<MessageBubbleState> _bubbleKey =
  GlobalKey<MessageBubbleState>();

  /// Called by EventList whenever the timeline has updated.
  /// Forwards to the bubble so it can drop stale optimistic entries.
  void reconcileBubble() {
    _bubbleKey.currentState?.reconcileOptimistic();
  }

  @override
  Widget build(BuildContext context) {
    final bubble = MessageBubble(
      key: _bubbleKey,
      timeline: widget.timeline,
      event: widget.event,
      room: widget.room,
      isOwn: widget.isOwn,
      onReacted: widget.onReacted,
      onReply: widget.onReply,
      onScrollToEvent: widget.onScrollToEvent,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
        widget.isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!widget.isOwn) ...[
            AvatarWidget(
                event: widget.event,
                resolveAvatarUrl: widget.resolveAvatarUrl),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: widget.isOwn
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.isOwn)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      widget.event.senderFromMemoryOrFallback
                          .calcDisplayname(),
                      style: const TextStyle(
                        color: Color(0xFF9AA4B2),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                widget.event.status.isSent
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