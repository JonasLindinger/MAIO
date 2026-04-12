import 'package:flutter/material.dart';
import 'package:maio/utils/notification_manager.dart';
import 'package:maio/widgets/chat/avatar.dart';
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
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();

  Timeline? _timeline;
  List<Event> _messageEvents = const [];
  bool _isRequestingHistory = false;
  bool _isSendingMedia = false;
  bool _isSearching = false;

  /// The event the user is currently replying to, or null.
  Event? _replyToEvent;

  final Map<String, String?> _avatarCache = {};

  @override
  void initState() {
    super.initState();
    NotificationManager.currentRoomId = widget.room.id;
    _timelineFuture = widget.room.getTimeline(
      onChange: (_) => _updateEvents(),
      onInsert: (_) => _updateEvents(),
      onRemove: (_) => _updateEvents(),
      onUpdate: _updateEvents,
    );
    _timelineFuture.then((tl) {
      _timeline = tl;
      _updateEvents();
      _markAsRead();
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _fillScreen());
    });
    _scrollController.addListener(_onScroll);
    _searchController.addListener(() {
      setState(() {});
    });
  }

  Future<void> _markAsRead() async {
    try {
      final latest = widget.room.lastEvent;
      if (latest != null) await widget.room.setReadMarker(latest.eventId);
    } catch (_) {}
  }

  @override
  void dispose() {
    NotificationManager.currentRoomId = null;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _sendController.dispose();
    _searchController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  static bool _isDisplayableMessage(Event e) =>
      e.type == 'm.room.message' || e.type == 'm.room.encrypted';

  void _updateEvents() {
    if (!mounted || _timeline == null) return;
    final next = _timeline!.events
        .where(_isDisplayableMessage)
        .toList(growable: false);

    setState(() => _messageEvents = next);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _fillScreen());
  }

  Future<void> _fillScreen() async {
    if (_isRequestingHistory) return;
    final tl = _timeline;
    if (tl == null) return;
    while (tl.canRequestHistory && !_isScrollable()) {
      await _fetchMoreHistory();
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
    }
  }

  bool _isScrollable() {
    if (!_scrollController.hasClients) return false;
    return _scrollController.position.maxScrollExtent > 0;
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isRequestingHistory) return;
    final tl = _timeline;
    if (tl == null || !tl.canRequestHistory) return;
    final pos = _scrollController.position;
    final buffer = pos.viewportDimension * 0.5;
    if (pos.pixels >= pos.maxScrollExtent - buffer) {
      _fetchMoreHistory().then((_) {
        if (mounted) _fillScreen();
      });
    }
  }

  Future<void> _fetchMoreHistory() async {
    if (_isRequestingHistory) return;
    final tl = _timeline;
    if (tl == null || !tl.canRequestHistory) return;
    _isRequestingHistory = true;
    if (mounted) setState(() {});
    try {
      await tl.requestHistory(historyCount: 50);
    } finally {
      _isRequestingHistory = false;
      if (mounted) setState(() {});
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
          widget.room.client, width: 48, height: 48);
      final token = widget.room.client.accessToken ?? '';
      final sep = uri.query.isEmpty ? '?' : '&';
      final url =
      token.isEmpty ? uri.toString() : '$uri${sep}access_token=$token';
      _avatarCache[id] = url;
      return url;
    } catch (_) {
      _avatarCache[id] = null;
      return null;
    }
  }

  void _startReply(Event event) {
    setState(() => _replyToEvent = event);
    _composerFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyToEvent = null);
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;

    List<Event> displayEvents = _messageEvents;
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      displayEvents = _messageEvents.where((e) =>
          e.body.toLowerCase().contains(query)
      ).toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10151D),
        foregroundColor: const Color(0xFFF2F4F7),
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: _isSearching ? 48 : 92,
        leading: _isSearching
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _isSearching = false;
              _searchController.clear();
            });
          },
        )
            : Row(
          children: [
            const BackButton(),
            RoomAvatar(room: room, client: room.client, radius: 16),
          ],
        ),
        title: _isSearching
            ? TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF2F4F7)),
          decoration: const InputDecoration(
            hintText: 'Search messages...',
            hintStyle: TextStyle(color: Color(0xFF667085)),
            border: InputBorder.none,
          ),
        )
            : Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Text(
            room.name.isEmpty ? room.getLocalizedDisplayname() : room.name,
            style: const TextStyle(
                color: Color(0xFFF2F4F7),
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
        ),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            ),
          if (_isSearching && _searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => _searchController.clear(),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _timeline == null
                  ? const Center(
                  child: CircularProgressIndicator.adaptive())
                  : EventList(
                events: displayEvents,
                timeline: _timeline!,
                room: room,
                scrollController: _scrollController,
                ownUserId: room.client.userID ?? '',
                resolveAvatarUrl: _resolveAvatarUrl,
                onReacted: () {
                  if (mounted) setState(() {});
                },
                onReply: _startReply,
                isLoadingHistory: _isRequestingHistory,
              ),
            ),
            InputBar(
              sendController: _sendController,
              composerFocusNode: _composerFocusNode,
              isSendingMedia: _isSendingMedia,
              room: room,
              replyToEvent: _replyToEvent,
              onCancelReply: _cancelReply,
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
