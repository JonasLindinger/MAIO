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

  const EventList({
    required this.events,
    required this.timeline,
    required this.room,
    required this.scrollController,
    required this.ownUserId,
    required this.resolveAvatarUrl,
    required this.onReacted
  });

  bool isVisibleInTimeline(Event e) {
    switch (e.type) {
      case "m.room.message":
        return true;

      case "m.room.encrypted":
        return true;

      case "m.room.redaction":
        return false;

      case "m.reaction":
        return false;

      case "m.room.member":
        return false;

      case "m.room.name":
        return false;

      case "m.room.topic":
        return false; // optional system info

      default:
        print("Can't handle: " + e.type);
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleEvents = events.where(isVisibleInTimeline).toList();

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: visibleEvents.length,
      itemBuilder: (context, index) {
        final event = visibleEvents[index];
        final isOwn = event.senderId == ownUserId;

        return MessageRow(
            key: ValueKey(event.eventId),
            event: event,
            timeline: timeline,
            room: room,
            isOwn: isOwn,
            resolveAvatarUrl: resolveAvatarUrl,
            onReacted: onReacted
        );
      },
    );
  }
}