import 'package:cached_network_image/cached_network_image.dart';
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

  Timeline? _timeline;
  List<Event> _events = const [];
  bool _isRequestingHistory = false;
  bool _isSendingMedia = false;

  // Resolved avatar URL strings, keyed by senderId. null = no avatar.
  final Map<String, String?> _avatarUrlCache = {};

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
    });
    _scrollController.addListener(_onScroll);
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
    final next = _timeline!.events
        .where((e) => e.relationshipEventId == null)
        .toList(growable: false);

    // Bail early — avoid setState if nothing the UI cares about changed
    if (next.length == _events.length) {
      bool same = true;
      for (int i = 0; i < next.length; i++) {
        if (next[i].eventId != _events[i].eventId ||
            next[i].status != _events[i].status) {
          same = false;
          break;
        }
      }
      if (same) return;
    }

    setState(() => _events = next);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isRequestingHistory) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
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

  /// Returns a resolved HTTPS URL for the sender's avatar, or null.
  /// Result is cached so the async work runs at most once per sender.
  Future<String?> _resolveAvatarUrl(Event event) async {
    final id = event.senderId;
    if (_avatarUrlCache.containsKey(id)) return _avatarUrlCache[id];
    final mxUri = event.senderFromMemoryOrFallback.avatarUrl;
    if (mxUri == null) {
      _avatarUrlCache[id] = null;
      return null;
    }
    try {
      final uri = await mxUri.getThumbnailUri(
        widget.room.client,
        width: 48,
        height: 48,
      );
      // Append access token once, store as plain string
      final token = widget.room.client.accessToken ?? '';
      final sep = uri.query.isEmpty ? '?' : '&';
      final url = token.isEmpty
          ? uri.toString()
          : '${uri}${sep}access_token=$token';
      _avatarUrlCache[id] = url;
      return url;
    } catch (_) {
      _avatarUrlCache[id] = null;
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
                  : _EventList(
                events: _events,
                timeline: _timeline!,
                room: room,
                scrollController: _scrollController,
                ownUserId: room.client.userID ?? '',
                resolveAvatarUrl: _resolveAvatarUrl,
              ),
            ),
            InputBar(
              sendController: _sendController,
              composerFocusNode: _composerFocusNode,
              isSendingMedia: _isSendingMedia,
              room: room,
              onSendMessage: () { if (mounted) setState(() {}); },
              onStartSendingMedia: () {
                if (mounted) setState(() => _isSendingMedia = true);
              },
              onFinishedSendingMedia: () {
                if (mounted) setState(() => _isSendingMedia = false);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List
// ─────────────────────────────────────────────────────────────────────────────

class _EventList extends StatelessWidget {
  final List<Event> events;
  final Timeline timeline;
  final Room room;
  final ScrollController scrollController;
  final String ownUserId;
  final Future<String?> Function(Event) resolveAvatarUrl;

  const _EventList({
    required this.events,
    required this.timeline,
    required this.room,
    required this.scrollController,
    required this.ownUserId,
    required this.resolveAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      reverse: true,
      // Keeps items alive across scroll so they don't re-render from scratch
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isOwn = event.senderId == ownUserId;
        return _MessageRow(
          key: ValueKey(event.eventId),
          event: event,
          timeline: timeline,
          room: room,
          isOwn: isOwn,
          resolveAvatarUrl: resolveAvatarUrl,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row
// ─────────────────────────────────────────────────────────────────────────────

class _MessageRow extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final Room room;
  final bool isOwn;
  final Future<String?> Function(Event) resolveAvatarUrl;

  const _MessageRow({
    super.key,
    required this.event,
    required this.timeline,
    required this.room,
    required this.isOwn,
    required this.resolveAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = RepaintBoundary(
      child: MessageBubble(
        timeline: timeline,
        event: event,
        room: room,
        isOwn: isOwn,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
        isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOwn) ...[
            _AvatarWidget(event: event, resolveAvatarUrl: resolveAvatarUrl),
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

// ─────────────────────────────────────────────────────────────────────────────
// Avatar — resolves once, then uses CachedNetworkImage for disk cache
// ─────────────────────────────────────────────────────────────────────────────

class _AvatarWidget extends StatefulWidget {
  final Event event;
  final Future<String?> Function(Event) resolveAvatarUrl;

  const _AvatarWidget({
    required this.event,
    required this.resolveAvatarUrl,
  });

  @override
  State<_AvatarWidget> createState() => _AvatarWidgetState();
}

class _AvatarWidgetState extends State<_AvatarWidget> {
  // Three states: null = not loaded yet, '' = no avatar, url = has avatar
  String? _url;
  bool _resolved = false;

  static const _placeholder = CircleAvatar(
    radius: 18,
    backgroundColor: Color(0xFF2A3441),
    child: Icon(Icons.person_outline, size: 18, color: Colors.white70),
  );

  @override
  void initState() {
    super.initState();
    widget.resolveAvatarUrl(widget.event).then((url) {
      if (mounted) setState(() { _url = url; _resolved = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved || (_url == null || _url!.isEmpty)) return _placeholder;

    return CachedNetworkImage(
      imageUrl: _url!,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: 18,
        backgroundImage: imageProvider,
        backgroundColor: const Color(0xFF2A3441),
      ),
      placeholder: (_, __) => _placeholder,
      errorWidget: (_, __, ___) => _placeholder,
      width: 36,
      height: 36,
      memCacheWidth: 72,
      memCacheHeight: 72,
    );
  }
}