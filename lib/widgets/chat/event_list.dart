import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'message_row.dart';

class EventList extends StatefulWidget {
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
  State<EventList> createState() => EventListState();
}

class EventListState extends State<EventList> {
  /// eventId -> GlobalKey for the MessageRow widget.
  final Map<String, GlobalKey<MessageRowState>> _rowKeys = {};

  /// eventId -> emoji -> set of userIds
  Map<String, Map<String, Set<String>>> _reactionCache = {};

  /// eventId -> event it is replying to (if any)
  Map<String, Event?> _replyCache = {};

  GlobalKey<MessageRowState> _rowKey(String eventId) =>
      _rowKeys.putIfAbsent(eventId, () => GlobalKey<MessageRowState>());

  @override
  void initState() {
    super.initState();
    _rebuildCaches();
  }

  @override
  void didUpdateWidget(EventList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events != widget.events || oldWidget.timeline != widget.timeline) {
      _rebuildCaches();
    }
  }

  void _rebuildCaches() {
    final reactions = <String, Map<String, Set<String>>>{};
    final replies = <String, Event?>{};
    final eventMap = <String, Event>{};

    // Build a map of all events in the timeline for O(1) lookup
    for (final e in widget.timeline.events) {
      eventMap[e.eventId] = e;
      if (e.type == EventTypes.Reaction) {
        final targetId = e.relationshipEventId;
        if (targetId == null) continue;

        final key = e.content
            .tryGetMap<String, dynamic>('m.relates_to')
            ?.tryGet<String>('key');
        if (key == null) continue;

        reactions.putIfAbsent(targetId, () => {});
        reactions[targetId]!.putIfAbsent(key, () => {});
        reactions[targetId]![key]!.add(e.senderId);
      }
    }

    // Resolve replies using the eventMap
    for (final e in widget.events) {
      final relatesTo = e.content.tryGetMap<String, dynamic>('m.relates_to');
      if (relatesTo == null) continue;
      final inReplyTo = relatesTo.tryGetMap<String, dynamic>('m.in_reply_to');
      final replyEventId = inReplyTo?.tryGet<String>('event_id');
      if (replyEventId == null) continue;

      replies[e.eventId] = eventMap[replyEventId];
    }

    _reactionCache = reactions;
    _replyCache = replies;
  }

  // ─── Scroll to event ───────────────────────────────────────────────────────
  // The ListView is reverse:true, meaning index 0 (newest) is at the bottom.
  // Scrollable.ensureVisible doesn't work reliably here because the context's
  // render box position is already flipped.  Instead we find the event's index,
  // compute a target scroll offset, and animate to it.

  void scrollToEvent(String eventId) {
    final index = widget.events.indexWhere((e) => e.eventId == eventId);
    if (index == -1) return; // not in loaded window

    final sc = widget.scrollController;
    if (!sc.hasClients) return;

    // Use ensureVisible via the row's context — works for items that are
    // already built.  For items outside the viewport we fall back to a
    // position-estimate scroll.
    final key = _rowKeys[eventId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        alignment: 0.5,
      );
      return;
    }

    // Item not currently built (outside lazy-build range). Estimate position:
    // In a reversed list, index 0 is at offset 0.
    const estimatedRowHeight = 72.0;
    final target = (index * estimatedRowHeight).clamp(0.0, sc.position.maxScrollExtent);
    sc.animateTo(target,
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final itemCount =
        widget.events.length + (widget.isLoadingHistory ? 1 : 0);

    return ListView.builder(
      controller: widget.scrollController,
      reverse: true,
      addRepaintBoundaries: true,
      addAutomaticKeepAlives: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == widget.events.length) {
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

        final event = widget.events[index];
        final isOwn = event.senderId == widget.ownUserId;

        return MessageRow(
          key: _rowKey(event.eventId),
          event: event,
          timeline: widget.timeline,
          room: widget.room,
          isOwn: isOwn,
          resolveAvatarUrl: widget.resolveAvatarUrl,
          onReacted: widget.onReacted,
          onReply: widget.onReply,
          onScrollToEvent: scrollToEvent,
          reactions: _reactionCache[event.eventId],
          replyToEvent: _replyCache[event.eventId],
        );
      },
    );
  }
}