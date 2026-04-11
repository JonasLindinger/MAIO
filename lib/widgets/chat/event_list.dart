import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'message_row.dart';

class EventList extends StatelessWidget {
  final List<Event> events;
  final Timeline timeline;
  final Room room;
  final ScrollController scrollController;
  final String ownUserId;
  final Future<String?> Function(Event) resolveAvatarUrl;
  final Function onReacted;
  final Function(Event)? onReply;
  final bool isLoadingHistory;

  const EventList({
    super.key,
    required this.events,
    required this.timeline,
    required this.room,
    required this.scrollController,
    required this.ownUserId,
    required this.resolveAvatarUrl,
    required this.onReacted,
    this.onReply,
    this.isLoadingHistory = false,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = events.length + (isLoadingHistory ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      addRepaintBoundaries: true,
      addAutomaticKeepAlives: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == events.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
            ),
          );
        }

        final event = events[index];
        final isOwn = event.senderId == ownUserId;

        return MessageRow(
          key: ValueKey(event.eventId),
          event: event,
          timeline: timeline,
          room: room,
          isOwn: isOwn,
          resolveAvatarUrl: resolveAvatarUrl,
          onReacted: onReacted,
          onReply: onReply,
        );
      },
    );
  }
}