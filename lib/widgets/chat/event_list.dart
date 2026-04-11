import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'message_bubble.dart';
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
  /// Used for both scroll-to-event and reconcileOptimistic.
  final Map<String, GlobalKey<MessageRowState>> _rowKeys = {};

  GlobalKey<MessageRowState> _rowKey(String eventId) =>
      _rowKeys.putIfAbsent(eventId, () => GlobalKey<MessageRowState>());

  @override
  void didUpdateWidget(EventList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Every time the parent pushes a new events list (i.e. the timeline fired
    // onChange/onInsert/onRemove), we tell every visible bubble to reconcile
    // its optimistic state against the now-updated timeline.  This is the only
    // place optimistic entries are cleared — no timers, no frame callbacks.
    if (oldWidget.events != widget.events) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final key in _rowKeys.values) {
          key.currentState?.reconcileBubble();
        }
      });
    }
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
    // average row height × index gives a rough offset in a reversed list.
    const estimatedRowHeight = 72.0;
    final target =
    (sc.position.maxScrollExtent - index * estimatedRowHeight)
        .clamp(0.0, sc.position.maxScrollExtent);
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
        );
      },
    );
  }
}