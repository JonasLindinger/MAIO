import 'package:flutter/material.dart';
import 'package:maio/Widgets/InputBar.dart';
import 'package:maio/Widgets/MessageBubble.dart';
import 'package:matrix/matrix.dart';

class RoomPage extends StatefulWidget {
  final Room room;
  const RoomPage({required this.room, super.key});

  @override
  _RoomPageState createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  late final Future<Timeline> _timelineFuture;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _sendController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();

  bool _isRequestingHistory = false;
  bool _isSendingMedia = false;

  @override
  void initState() {
    _timelineFuture = widget.room.getTimeline(
      onChange: (_) {
        if (!mounted) return;
        setState(() {});
      },
      onInsert: (_) {
        if (!mounted) return;
        setState(() {});
      },
      onRemove: (_) {
        if (!mounted) return;
        setState(() {});
      },
      onUpdate: () {
        if (!mounted) return;
        setState(() {});
      },
    );

    _scrollController.addListener(_onScroll);
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _sendController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() async {
    if (!_scrollController.hasClients || _isRequestingHistory) return;

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final timeline = await _timelineFuture;
      _isRequestingHistory = true;
      try {
        await timeline.requestHistory();
      } finally {
        _isRequestingHistory = false;
      }
    }
  }

  bool _isOwnMessage(Event event) {
    return event.senderId == widget.room.client.userID;
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10151D),
        foregroundColor: const Color(0xFFF2F4F7),
        elevation: 0,
        title: Text(
          room.name.isEmpty ? room.getLocalizedDisplayname() : room.name,
          style: const TextStyle(color: Color(0xFFF2F4F7)),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<Timeline>(
                future: _timelineFuture,
                builder: (context, snapshot) {
                  final timeline = snapshot.data;
                  if (timeline == null) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(),
                    );
                  }

                  final events = timeline.events
                      .where((event) => event.relationshipEventId == null)
                      .toList();

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final isOwn = _isOwnMessage(event);

                      return TweenAnimationBuilder<double>(
                        key: ValueKey(event.eventId ?? '${event.senderId}_$index'),
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 12 * (1 - value)),
                              child: child,
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: isOwn
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isOwn) ...[
                                FutureBuilder<Uri?>(
                                  future: event.senderFromMemoryOrFallback
                                      .avatarUrl ==
                                      null
                                      ? Future.value(null)
                                      : event
                                      .senderFromMemoryOrFallback.avatarUrl!
                                      .getThumbnailUri(
                                    widget.room.client,
                                    width: 48,
                                    height: 48,
                                  ),
                                  builder: (context, snapshot) {
                                    final uri = snapshot.data;
                                    if (uri == null) {
                                      return const CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Color(0xFF2A3441),
                                        child: Icon(
                                          Icons.person_outline,
                                          size: 18,
                                          color: Colors.white70,
                                        ),
                                      );
                                    }

                                    return CircleAvatar(
                                      radius: 18,
                                      foregroundImage: NetworkImage(
                                        uri.toString(),
                                        headers: {
                                          'Authorization':
                                          'Bearer ${widget.room.client.accessToken}',
                                        },
                                      ),
                                      onForegroundImageError: (_, __) {},
                                      backgroundColor: const Color(0xFF2A3441),
                                      child: const Icon(
                                        Icons.person_outline,
                                        size: 18,
                                        color: Colors.white70,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: isOwn
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (!isOwn)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 4,
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          event.senderFromMemoryOrFallback.calcDisplayname(),
                                          style: const TextStyle(
                                            color: Color(0xFF9AA4B2),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    AnimatedScale(
                                      scale: event.status.isSent ? 1 : 0.96,
                                      duration:
                                      const Duration(milliseconds: 180),
                                      curve: Curves.easeOut,
                                      child: AnimatedOpacity(
                                        opacity: event.status.isSent ? 1 : 0.6,
                                        duration:
                                        const Duration(milliseconds: 150),
                                        child: MessageBubble(
                                          timeline: timeline,
                                          event: event,
                                          room: room,
                                          isOwn: _isOwnMessage(event),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            InputBar(
              sendController: _sendController,
              composerFocusNode: _composerFocusNode,
              isSendingMedia: _isSendingMedia,
              room: room,
              onSendMessage: () {
                if (mounted) {
                  setState(() {});
                }
              },
              onStartSendingMedia: () {
                if (mounted) {
                  setState(() => _isSendingMedia = true);
                }
              },
              onFinishedSendingMedia: () {
                if (mounted) {
                  setState(() => _isSendingMedia = false);
                }
              }
            ),
          ],
        ),
      ),
    );
  }
}