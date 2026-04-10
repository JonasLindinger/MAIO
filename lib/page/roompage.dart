import 'package:flutter/material.dart';
import 'package:maio/widgets/chat/input_bar.dart';
import 'package:matrix/matrix.dart';

import '../widgets/chat/event_list.dart';

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

  Timeline? _timeline;
  List<Event> _events = const [];
  bool _isRequestingHistory = false;
  bool _isSendingMedia = false;

  // Resolved avatar URL strings, keyed by senderId
  final Map<String, String?> _avatarCache = {};

  @override
  void initState() {
    super.initState();
    _timelineFuture = widget.room.getTimeline(
      onChange: (_) => _updateEvents(),
      onInsert: (_) => _updateEvents(),
      onRemove: (_) => _updateEvents(),
      onUpdate: _updateEvents,
    );
    _timelineFuture.then((tl) {
      _timeline = tl;
      _updateEvents();
      // Mark all messages as read when the timeline is ready
      _markAsRead();
    });
    _scrollController.addListener(_onScroll);
  }

  /// Send a read receipt for the latest event, clearing the notification badge.
  Future<void> _markAsRead() async {
    try {
      final latestEvent = widget.room.lastEvent;
      if (latestEvent != null) {
        await widget.room.setReadMarker(latestEvent.eventId);
      }
    } catch (_) {
      // Non-critical — ignore failures silently
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _sendController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  void _updateEvents() {
    if (!mounted || _timeline == null) return;

    final next = List<Event>.from(_timeline!.events);

    if (next.length == _events.length) return;

    setState(() => _events = next);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isRequestingHistory) return;

    final tl = _timeline;
    if (tl == null || !tl.canRequestHistory) return;

    final position = _scrollController.position;

    // only trigger when near top in reverse list
    if (position.pixels <= 300) {
      _fetchMoreHistory();
    }
  }

  Future<void> _fetchMoreHistory() async {
    _isRequestingHistory = true;
    try {
      final tl = await _timelineFuture;
      await tl.requestHistory();
    } finally {
      if (mounted) _isRequestingHistory = false;
    }
  }

  Future<String?> _resolveAvatarUrl(Event event) async {
    final id = event.senderId;
    if (_avatarCache.containsKey(id)) return _avatarCache[id];
    final mxUri = event.senderFromMemoryOrFallback.avatarUrl;
    if (mxUri == null) {
      _avatarCache[id] = null;
      return null;
    }
    try {
      final uri = await mxUri.getThumbnailUri(
        widget.room.client,
        width: 48,
        height: 48,
      );
      final token = widget.room.client.accessToken ?? '';
      final sep = uri.query.isEmpty ? '?' : '&';
      final url = token.isEmpty ? uri.toString() : '$uri${sep}access_token=$token';
      _avatarCache[id] = url;
      return url;
    } catch (_) {
      _avatarCache[id] = null;
      return null;
    }
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
        titleSpacing: 0,
        title: Text(
          room.name.isEmpty ? room.getLocalizedDisplayname() : room.name,
          style: const TextStyle(
              color: Color(0xFFF2F4F7),
              fontSize: 16,
              fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _timeline == null
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : EventList(
                events: _events,
                timeline: _timeline!,
                room: room,
                scrollController: _scrollController,
                ownUserId: room.client.userID ?? '',
                resolveAvatarUrl: _resolveAvatarUrl,
                onReacted: () {
                  // setState(() {});
                },
              ),
            ),
            InputBar(
              sendController: _sendController,
              composerFocusNode: _composerFocusNode,
              isSendingMedia: _isSendingMedia,
              room: room,
              onSendMessage: () {
                if (mounted) setState(() {});
                _markAsRead();
              },
              onStartSendingMedia: () {
                if (mounted) setState(() => _isSendingMedia = true);
              },
              onFinishedSendingMedia: () {
                if (mounted) setState(() => _isSendingMedia = false);
                _markAsRead();
              },
            ),
          ],
        ),
      ),
    );
  }
}