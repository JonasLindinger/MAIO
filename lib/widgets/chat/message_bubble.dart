import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'attachment_preview.dart';
import 'formatted_message.dart';

class MessageBubble extends StatefulWidget {
  final Timeline timeline;
  final Event event;
  final Room room;
  final bool isOwn;
  final Function onReacted;
  final Function(Event)? onReply;
  final void Function(String eventId)? onScrollToEvent;

  const MessageBubble({
    super.key,
    required this.timeline,
    required this.event,
    required this.room,
    required this.isOwn,
    required this.onReacted,
    this.onReply,
    this.onScrollToEvent,
  });

  @override
  MessageBubbleState createState() => MessageBubbleState();
}

class MessageBubbleState extends State<MessageBubble> {
  /// emoji -> true (added optimistically) | false (removed optimistically)
  final Map<String, bool> _optimistic = {};

  double _dragOffset = 0;
  bool _replyArmed = false;

  // ─── Public API called by EventList ────────────────────────────────────────

  /// Called by EventList every time the timeline updates (onChange/onInsert/
  /// onRemove). We check each pending optimistic entry: if the server state
  /// now matches the intended outcome we drop the entry; if it contradicts
  /// we also drop it (nothing better to do). This is the ONLY place we clear
  /// optimistic entries — never on a fixed timer or frame callback.
  void reconcileOptimistic() {
    if (_optimistic.isEmpty) return;
    final ownId = widget.room.client.userID ?? '';
    final serverReactions = _reactionsFromTimeline();
    final toRemove = <String>[];
    _optimistic.forEach((emoji, addedOptimistically) {
      final serverHasIt =
          serverReactions[emoji]?.users.contains(ownId) ?? false;
      // If server now reflects what we intended, or has gone the other way
      // (rare error case), the optimistic entry is stale — drop it.
      if (addedOptimistically == serverHasIt || !addedOptimistically == !serverHasIt) {
        toRemove.add(emoji);
      }
    });
    if (toRemove.isNotEmpty && mounted) {
      setState(() {
        for (final e in toRemove) {
          _optimistic.remove(e);
        }
      });
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Strips the Matrix plaintext reply-fallback prefix:
  ///   > <@user:server> quoted text\n\n real text
  static String stripReplyFallback(String body) {
    if (!body.startsWith('> ')) return body;
    final lines = body.split('\n');
    int i = 0;
    while (i < lines.length && lines[i].startsWith('> ')) {
      i++;
    }
    // Skip the blank separator line.
    if (i < lines.length && lines[i].trim().isEmpty) i++;
    return lines.sublist(i).join('\n').trim();
  }

  String? _eventBody() {
    final raw = widget.event.getDisplayEvent(widget.timeline).body.trim();
    if (raw.isEmpty) return null;
    final body = stripReplyFallback(raw);
    if (!widget.event.hasAttachment) return body.isEmpty ? null : body;
    final filename = widget.event.content['filename'];
    if (filename != null && filename != body) return body.isEmpty ? null : body;
    return null;
  }

  Event? _replyToEvent() {
    final relatesTo =
    widget.event.content.tryGetMap<String, dynamic>('m.relates_to');
    if (relatesTo == null) return null;
    final inReplyTo =
    relatesTo.tryGetMap<String, dynamic>('m.in_reply_to');
    final replyEventId = inReplyTo?.tryGet<String>('event_id');
    if (replyEventId == null) return null;
    try {
      return widget.timeline.events
          .firstWhere((e) => e.eventId == replyEventId);
    } catch (_) {
      return null;
    }
  }

  // ─── Reactions ─────────────────────────────────────────────────────────────

  Map<String, _ReactionData> _reactionsFromTimeline() {
    final map = <String, Set<String>>{};
    for (final e in widget.timeline.events) {
      if (e.type != EventTypes.Reaction) continue;
      if (e.relationshipEventId != widget.event.eventId) continue;
      final key = e.content
          .tryGetMap<String, dynamic>('m.relates_to')
          ?.tryGet<String>('key');
      if (key == null) continue;
      map.putIfAbsent(key, () => {});
      map[key]!.add(e.senderId);
    }
    return map.map((k, v) => MapEntry(k, _ReactionData(users: v)));
  }

  Map<String, _ReactionData> _reactions() {
    final ownId = widget.room.client.userID ?? '';
    final map = <String, Set<String>>{};

    for (final e in widget.timeline.events) {
      if (e.type != EventTypes.Reaction) continue;
      if (e.relationshipEventId != widget.event.eventId) continue;
      final key = e.content
          .tryGetMap<String, dynamic>('m.relates_to')
          ?.tryGet<String>('key');
      if (key == null) continue;
      map.putIfAbsent(key, () => {});
      map[key]!.add(e.senderId);
    }

    _optimistic.forEach((emoji, added) {
      if (added) {
        map.putIfAbsent(emoji, () => {});
        map[emoji]!.add(ownId);
      } else {
        map[emoji]?.remove(ownId);
        if (map[emoji]?.isEmpty ?? false) map.remove(emoji);
      }
    });

    return map.map((k, v) => MapEntry(k, _ReactionData(users: v)));
  }

  Future<void> _react(String emoji) async {
    final ownId = widget.room.client.userID ?? '';
    final serverReactions = _reactionsFromTimeline();
    final isMine = serverReactions[emoji]?.users.contains(ownId) ?? false;

    // Show intended end-state immediately.
    setState(() => _optimistic[emoji] = !isMine);

    try {
      if (isMine) {
        for (final e in widget.timeline.events) {
          if (e.type == EventTypes.Reaction &&
              e.relationshipEventId == widget.event.eventId &&
              e.senderId == ownId) {
            final key = e.content
                .tryGetMap<String, dynamic>('m.relates_to')
                ?.tryGet<String>('key');
            if (key == emoji) {
              await widget.room.redactEvent(e.eventId);
              break;
            }
          }
        }
      } else {
        await widget.room.sendReaction(widget.event.eventId, emoji);
      }
      // Notify the parent so it calls setState and then reconcileOptimistic
      // on all visible bubbles — the optimistic entry will be cleared as soon
      // as the timeline actually reflects the change.
      widget.onReacted();
    } catch (_) {
      // Revert immediately on network failure.
      if (mounted) setState(() => _optimistic.remove(emoji));
    }
  }

  // ─── UI actions ────────────────────────────────────────────────────────────

  void _showContextMenu() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ContextMenuSheet(
        onReply: widget.onReply != null
            ? () {
          Navigator.pop(context);
          widget.onReply!(widget.event);
        }
            : null,
        onReact: () {
          Navigator.pop(context);
          _showEmojiPicker();
        },
      ),
    );
  }

  void _showEmojiPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EmojiSheet(
        onPick: (emoji) {
          Navigator.pop(context);
          _react(emoji);
        },
      ),
    );
  }

  void _showReactionDetail(String emoji, _ReactionData data) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ReactionDetailSheet(
        emoji: emoji,
        data: data,
        room: widget.room,
      ),
    );
  }

  // ─── Swipe to reply ────────────────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) {
    if (widget.onReply == null) return;
    final delta = widget.isOwn ? -d.delta.dx : d.delta.dx;
    if (delta < 0 && _dragOffset <= 0) return;

    final newOffset = (_dragOffset + delta).clamp(0.0, 72.0);
    setState(() => _dragOffset = newOffset);

    if (newOffset >= 64 && !_replyArmed) {
      _replyArmed = true;
      HapticFeedback.mediumImpact();
    }
    if (newOffset < 64 && _replyArmed) {
      _replyArmed = false;
      HapticFeedback.lightImpact();
    }
  }

  void _onDragEnd(DragEndDetails _) {
    if (_replyArmed) widget.onReply?.call(widget.event);
    setState(() {
      _dragOffset = 0;
      _replyArmed = false;
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bubbleColor =
    widget.isOwn ? const Color(0xFF2E7DFF) : const Color(0xFF1C2430);
    final body = _eventBody();
    final reactions = _reactions();
    final ownId = widget.room.client.userID ?? '';
    final replyEvent = _replyToEvent();

    final bubble = GestureDetector(
      onLongPress: _showContextMenu,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(widget.isOwn ? 18 : 6),
            bottomRight: Radius.circular(widget.isOwn ? 6 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyEvent != null)
              _ReplyPreview(
                event: replyEvent,
                isOwn: widget.isOwn,
                onTap: widget.onScrollToEvent != null
                    ? () => widget.onScrollToEvent!(replyEvent.eventId)
                    : null,
              ),
            if (widget.event.hasAttachment) ...[
              AttachmentPreview(
                timeline: widget.timeline,
                room: widget.room,
                event: widget.event,
                isOwn: widget.isOwn,
              ),
              if (body != null && body.isNotEmpty) ...[
                const SizedBox(height: 8),
                FormattedMessage(text: body),
              ],
            ] else
              FormattedMessage(text: body ?? ''),
          ],
        ),
      ),
    );

    final replyHint = AnimatedOpacity(
      opacity: (_dragOffset / 64).clamp(0.0, 1.0),
      duration: Duration.zero,
      child: Transform.scale(
        scale: (_dragOffset / 64).clamp(0.4, 1.0),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _replyArmed
                ? const Color(0xFF2E7DFF).withOpacity(0.35)
                : Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.reply,
            color: _replyArmed ? const Color(0xFF8BBFFF) : Colors.white70,
            size: 18,
          ),
        ),
      ),
    );

    final swipeable = GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (!widget.isOwn)
            Positioned(
                left: -40,
                top: 0,
                bottom: 0,
                child: Center(child: replyHint)),
          if (widget.isOwn)
            Positioned(
                right: -40,
                top: 0,
                bottom: 0,
                child: Center(child: replyHint)),
          Transform.translate(
            offset: Offset(widget.isOwn ? -_dragOffset : _dragOffset, 0),
            child: bubble,
          ),
        ],
      ),
    );

    if (reactions.isEmpty) return swipeable;

    return Column(
      crossAxisAlignment:
      widget.isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        swipeable,
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: reactions.entries.map((entry) {
              final isMine = entry.value.users.contains(ownId);
              return GestureDetector(
                onTap: () => _react(entry.key),
                onLongPress: () =>
                    _showReactionDetail(entry.key, entry.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: isMine
                        ? const Color(0xFF2E7DFF).withOpacity(0.2)
                        : const Color(0xFF1C2430),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isMine
                          ? const Color(0xFF2E7DFF).withOpacity(0.65)
                          : const Color(0xFF2E3D52),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(entry.key,
                          style: const TextStyle(
                              fontSize: 15, height: 1.1)),
                      const SizedBox(width: 5),
                      Text(
                        '${entry.value.count}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isMine
                              ? const Color(0xFF8BBFFF)
                              : const Color(0xFF9AA4B2),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ─── Reply preview (inside bubble) ───────────────────────────────────────────

class _ReplyPreview extends StatelessWidget {
  final Event event;
  final bool isOwn;
  final VoidCallback? onTap;

  const _ReplyPreview({
    required this.event,
    required this.isOwn,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = event.senderFromMemoryOrFallback.calcDisplayname();
    final strippedBody =
    MessageBubbleState.stripReplyFallback(event.body.trim());
    final preview = event.hasAttachment
        ? '📎 Attachment'
        : (strippedBody.length > 80
        ? '${strippedBody.substring(0, 80)}…'
        : strippedBody);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(
              color: isOwn
                  ? Colors.white.withOpacity(0.6)
                  : const Color(0xFF4C8DF6),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isOwn
                    ? Colors.white.withOpacity(0.85)
                    : const Color(0xFF4C8DF6),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              preview,
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withOpacity(0.65)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Context menu ─────────────────────────────────────────────────────────────

class _ContextMenuSheet extends StatelessWidget {
  final VoidCallback? onReply;
  final VoidCallback onReact;

  const _ContextMenuSheet({this.onReply, required this.onReact});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF13181F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A4352),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            if (onReply != null)
              _MenuItem(
                  icon: Icons.reply_rounded,
                  label: 'Reply',
                  onTap: onReply!),
            _MenuItem(
                icon: Icons.add_reaction_outlined,
                label: 'React',
                onTap: onReact),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFF2F4F7), size: 22),
            const SizedBox(width: 16),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFFF2F4F7),
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ─── Emoji picker ─────────────────────────────────────────────────────────────

class _EmojiSheet extends StatelessWidget {
  final void Function(String) onPick;
  const _EmojiSheet({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: EmojiPicker(
          onEmojiSelected: (_, emoji) => onPick(emoji.emoji),
          config: Config(
            height: 320,
            checkPlatformCompatibility: true,
            emojiViewConfig: EmojiViewConfig(
              emojiSizeMax: 28 *
                  (foundation.defaultTargetPlatform == TargetPlatform.iOS
                      ? 1.20
                      : 1.0),
              backgroundColor: const Color(0xFF13181F),
            ),
            viewOrderConfig: const ViewOrderConfig(
              top: EmojiPickerItem.categoryBar,
              middle: EmojiPickerItem.emojiView,
              bottom: EmojiPickerItem.searchBar,
            ),
            categoryViewConfig: const CategoryViewConfig(
              backgroundColor: Color(0xFF13181F),
              iconColorSelected: Color(0xFF4C8DF6),
              indicatorColor: Color(0xFF4C8DF6),
            ),
            searchViewConfig: SearchViewConfig(
              backgroundColor: const Color(0xFF13181F),
              buttonIconColor: const Color(0xFF4C8DF6),
            ),
            bottomActionBarConfig: const BottomActionBarConfig(
              backgroundColor: Color(0xFF13181F),
              buttonIconColor: const Color(0xFF9AA4B2),
            ),
            skinToneConfig: const SkinToneConfig(),
          ),
        ),
      ),
    );
  }
}

// ─── Reaction detail bottom sheet ────────────────────────────────────────────

class _ReactionDetailSheet extends StatefulWidget {
  final String emoji;
  final _ReactionData data;
  final Room room;

  const _ReactionDetailSheet({
    required this.emoji,
    required this.data,
    required this.room,
  });

  @override
  State<_ReactionDetailSheet> createState() => _ReactionDetailSheetState();
}

class _ReactionDetailSheetState extends State<_ReactionDetailSheet> {
  final Map<String, String> _names = {};
  final Map<String, String?> _avatarUrls = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolveMembers();
  }

  Future<void> _resolveMembers() async {
    final room = widget.room;
    final client = room.client;
    final memberStates = room.states['m.room.member'] ?? <String, Event>{};

    for (final userId in widget.data.users) {
      final stateEvent = memberStates[userId];
      _names[userId] =
          stateEvent?.content.tryGet<String>('displayname') ??
              userId.split(':').first.replaceFirst('@', '');

      final avatarMxc = stateEvent?.content.tryGet<String>('avatar_url');
      if (avatarMxc != null && avatarMxc.startsWith('mxc://')) {
        try {
          final mxcUri = Uri.parse(avatarMxc);
          final thumbUri =
          await mxcUri.getThumbnailUri(client, width: 48, height: 48);
          final token = client.accessToken ?? '';
          final sep = thumbUri.query.isEmpty ? '?' : '&';
          _avatarUrls[userId] = token.isEmpty
              ? thumbUri.toString()
              : '$thumbUri${sep}access_token=$token';
        } catch (_) {
          _avatarUrls[userId] = null;
        }
      } else {
        _avatarUrls[userId] = null;
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final userIds = widget.data.users.toList();
    final ownId = widget.room.client.userID ?? '';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF13181F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A4352),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(widget.emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 4),
            Text(
              '${widget.data.count} '
                  '${widget.data.count == 1 ? 'reaction' : 'reactions'}',
              style:
              const TextStyle(color: Color(0xFF9AA4B2), fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF1D2530), height: 1),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: userIds.length,
                  separatorBuilder: (_, __) =>
                  const Divider(color: Color(0xFF1D2530), height: 1),
                  itemBuilder: (_, i) {
                    final userId = userIds[i];
                    final name = _names[userId] ?? userId;
                    final avatarUrl = _avatarUrls[userId];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: Row(
                        children: [
                          _Avatar(
                              userId: userId,
                              name: name,
                              avatarUrl: avatarUrl),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                  color: Color(0xFFF2F4F7),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (userId == ownId)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7DFF)
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('You',
                                  style: TextStyle(
                                      color: Color(0xFF4C8DF6),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String userId;
  final String name;
  final String? avatarUrl;

  const _Avatar(
      {required this.userId, required this.name, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final fallback = CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFF2A3441),
      child: Text(initials,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
    );

    if (avatarUrl == null) return fallback;

    return CachedNetworkImage(
      imageUrl: avatarUrl!,
      imageBuilder: (_, img) => CircleAvatar(
        radius: 18,
        backgroundImage: img,
        backgroundColor: const Color(0xFF2A3441),
      ),
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
      width: 36,
      height: 36,
    );
  }
}

// ─── Data ─────────────────────────────────────────────────────────────────────

class _ReactionData {
  final Set<String> users;
  const _ReactionData({required this.users});
  int get count => users.length;
}