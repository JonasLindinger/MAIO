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

  const MessageBubble({
    super.key,
    required this.timeline,
    required this.event,
    required this.room,
    required this.isOwn,
    required this.onReacted,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  // Optimistic overlay: emoji -> delta (+1 or -1) applied before server confirms
  final Map<String, int> _optimistic = {};

  String? _eventBody() {
    final body = widget.event.getDisplayEvent(widget.timeline).body.trim();
    if (body.isEmpty) return null;
    if (!widget.event.hasAttachment) return body;
    final filename = widget.event.content['filename'];
    if (filename != null && filename != body) return body;
    return null;
  }

  // Reactions from the timeline, merged with optimistic deltas
  Map<String, _ReactionData> _reactions() {
    final ownId = widget.room.client.userID ?? '';
    // Map: emoji -> {count, myReactionEventId}
    final map = <String, _ReactionData>{};

    for (final e in widget.timeline.events) {
      if (e.type == EventTypes.Reaction &&
          e.relationshipEventId == widget.event.eventId) {
        final key = e.content
            .tryGetMap<String, dynamic>('m.relates_to')
            ?.tryGet<String>('key');
        if (key == null) continue;
        final existing = map[key] ?? _ReactionData(count: 0, myEventId: null);
        map[key] = _ReactionData(
          count: existing.count + 1,
          myEventId: e.senderId == ownId ? e.eventId : existing.myEventId,
        );
      }
    }

    // Apply optimistic deltas
    _optimistic.forEach((emoji, delta) {
      final existing = map[emoji];

      if (delta < 0) {
        map.remove(emoji);
        return;
      }

      if (delta > 0) {
        final alreadyMine = existing?.myEventId != null;

        // Only add if *I* haven't reacted yet
        if (!alreadyMine) {
          if (existing != null) {
            map[emoji] = _ReactionData(
              count: existing.count + 1,
              myEventId: existing.myEventId,
            );
          } else {
            map[emoji] = _ReactionData(count: 1, myEventId: null);
          }
        }
      }
    });

    // Remove zeros
    map.removeWhere((_, v) => v.count <= 0);
    return map;
  }

  Future<void> _react(String emoji) async {
    final reactions = _reactions();
    final ownId = widget.room.client.userID ?? '';

    // Determine if I have reacted (INCLUDING optimistic state)
    final hasReacted = (() {
      // Check real reactions
      for (final e in widget.timeline.events) {
        if (e.type == EventTypes.Reaction &&
            e.relationshipEventId == widget.event.eventId &&
            e.senderId == ownId) {
          final key = e.content
              .tryGetMap<String, dynamic>('m.relates_to')
              ?.tryGet<String>('key');
          if (key == emoji) return true;
        }
      }

      // Check optimistic override
      final delta = _optimistic[emoji] ?? 0;
      if (delta > 0) return true;
      if (delta < 0) return false;

      return false;
    })();

    // Find actual reaction event (only needed for unreact)
    Event? myReactionEvent;
    for (final e in widget.timeline.events) {
      if (e.type == EventTypes.Reaction &&
          e.relationshipEventId == widget.event.eventId &&
          e.senderId == ownId) {
        final key = e.content
            .tryGetMap<String, dynamic>('m.relates_to')
            ?.tryGet<String>('key');
        if (key == emoji) {
          myReactionEvent = e;
          break;
        }
      }
    }

    if (hasReacted) {
      // UNREACT
      setState(() => _optimistic[emoji] = -1);

      try {
        if (myReactionEvent != null) {
          await widget.room.redactEvent(myReactionEvent.eventId);
        }

        // WAIT for sync to catch up
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          setState(() => _cleanupOptimistic());
        });

      } catch (_) {
        if (mounted) {
          setState(() => _optimistic.remove(emoji));
        }
      }
    }
    else {
      // REACT
      setState(() => _optimistic[emoji] = 1);

      try {
        await widget.room.sendReaction(widget.event.eventId, emoji);

        // WAIT for sync to catch up
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          setState(() => _cleanupOptimistic());
        });

      } catch (_) {
        if (mounted) {
          setState(() => _optimistic.remove(emoji));
        }
      }
    }

    widget.onReacted();
  }

  void _cleanupOptimistic() {
    final ownId = widget.room.client.userID ?? '';

    for (final emoji in _optimistic.keys.toList()) {
      final delta = _optimistic[emoji]!;

      bool existsOnServer = false;

      for (final e in widget.timeline.events) {
        if (e.type == EventTypes.Reaction &&
            e.relationshipEventId == widget.event.eventId &&
            e.senderId == ownId) {
          final key = e.content
              .tryGetMap<String, dynamic>('m.relates_to')
              ?.tryGet<String>('key');

          if (key == emoji) {
            existsOnServer = true;
            break;
          }
        }
      }

      // If server state matches what we wanted → cleanup
      if ((delta > 0 && existsOnServer) ||
          (delta < 0 && !existsOnServer)) {
        _optimistic.remove(emoji);
      }
    }
  }

  void _showPicker() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EmojiPicker(
        onEmojiSelected: (Category? category, Emoji emoji) {
          // Do something when emoji is tapped (optional)
          Navigator.pop(context);
          _react(emoji.emoji);
        },
        onBackspacePressed: () {
          // Do something when the user taps the backspace button (optional)
          // Set it to null to hide the Backspace-Button
        },
        config: Config(
          height: 256,
          emojiTextStyle: TextStyle(
            backgroundColor: const Color(0xFFF2F2F2)
          ),
          checkPlatformCompatibility: true,
          emojiViewConfig: EmojiViewConfig(
            // Issue: https://github.com/flutter/flutter/issues/28894
            emojiSizeMax: 28 *
                (foundation.defaultTargetPlatform == TargetPlatform.iOS
                    ?  1.20
                    :  1.0),
          ),
          viewOrderConfig: const ViewOrderConfig(
            top: EmojiPickerItem.categoryBar,
            middle: EmojiPickerItem.emojiView,
            bottom: EmojiPickerItem.searchBar,
          ),
          skinToneConfig: const SkinToneConfig(),
          categoryViewConfig: const CategoryViewConfig(),
          bottomActionBarConfig: const BottomActionBarConfig(),
          searchViewConfig: const SearchViewConfig(),
        ),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = widget.isOwn ? const Color(0xFF2E7DFF) : const Color(0xFF1C2430);
    final body = _eventBody();
    final reactions = _reactions();
    final ownId = widget.room.client.userID ?? '';

    // Check which emojis the current user has reacted with
    final myReactions = <String>{};

    // Real reactions from server
    for (final e in widget.timeline.events) {
      if (e.type == EventTypes.Reaction &&
          e.relationshipEventId == widget.event.eventId &&
          e.senderId == ownId) {
        final key = e.content
            .tryGetMap<String, dynamic>('m.relates_to')
            ?.tryGet<String>('key');
        if (key != null) myReactions.add(key);
      }
    }

    // Apply optimistic changes
    _optimistic.forEach((emoji, delta) {
      if (delta > 0) {
        myReactions.add(emoji);
      } else if (delta < 0) {
        myReactions.remove(emoji); // force removal
      }
    });

    final bubble = GestureDetector(
      onLongPress: _showPicker,
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
              color: Colors.black.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: widget.event.hasAttachment
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        )
            : FormattedMessage(text: body ?? ''),
      ),
    );

    if (reactions.isEmpty) return bubble;

    return Column(
      crossAxisAlignment: widget.isOwn
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble,
        const SizedBox(height: 4),
        // Reactions aligned flush with the bubble edge
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            alignment: WrapAlignment.start,
            children: reactions.entries.map((entry) {
              final isMine = myReactions.contains(entry.key);
              return GestureDetector(
                onTap: () => _react(entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: isMine
                        ? const Color(0xFF2E7DFF).withOpacity(0.22)
                        : const Color(0xFF1C2430),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isMine
                          ? const Color(0xFF2E7DFF).withOpacity(0.7)
                          : const Color(0xFF2E3D52),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(entry.key,
                          style: const TextStyle(fontSize: 15, height: 1.1)),
                      const SizedBox(width: 4),
                      Text(
                        '${entry.value.count}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isMine
                              ? const Color(0xFF8BBFFF)
                              : const Color(0xFF9AA4B2),
                          fontWeight: FontWeight.w600,
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

class _ReactionData {
  final int count;
  final String? myEventId;
  const _ReactionData({required this.count, required this.myEventId});
}