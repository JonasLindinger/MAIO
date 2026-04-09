import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maio/Widgets/FormattedMessage.dart';
import 'package:matrix/matrix.dart';
import 'AttachmentPreview.dart';

class MessageBubble extends StatefulWidget {
  final Timeline timeline;
  final Event event;
  final Room room;
  final bool isOwn;

  const MessageBubble({
    super.key,
    required this.timeline,
    required this.event,
    required this.room,
    required this.isOwn,
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
      if (existing != null) {
        final newCount = existing.count + delta;
        map[emoji] = _ReactionData(
          count: newCount < 0 ? 0 : newCount,
          myEventId: existing.myEventId,
        );
      } else if (delta > 0) {
        map[emoji] = _ReactionData(count: 1, myEventId: null);
      }
    });

    // Remove zeros
    map.removeWhere((_, v) => v.count <= 0);
    return map;
  }

  Future<void> _react(String emoji) async {
    final reactions = _reactions();
    final existing = reactions[emoji];
    final ownId = widget.room.client.userID ?? '';

    // Check if user already reacted with this emoji
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

    if (myReactionEvent != null) {
      // Unreact — redact the reaction event
      setState(() => _optimistic[emoji] = (_optimistic[emoji] ?? 0) - 1);
      try {
        await widget.room.redactEvent(myReactionEvent.eventId);
      } catch (_) {
        // Roll back
        if (mounted) setState(() => _optimistic[emoji] = (_optimistic[emoji] ?? 0) + 1);
      }
    } else {
      // Add reaction
      setState(() => _optimistic[emoji] = (_optimistic[emoji] ?? 0) + 1);
      try {
        await widget.room.sendReaction(widget.event.eventId, emoji);
      } catch (_) {
        if (mounted) setState(() => _optimistic[emoji] = (_optimistic[emoji] ?? 0) - 1);
      }
    }
  }

  void _showPicker() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmojiPickerSheet(
        onPick: (emoji) {
          Navigator.pop(context);
          _react(emoji);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor =
    widget.isOwn ? const Color(0xFF2E7DFF) : const Color(0xFF1C2430);
    final body = _eventBody();
    final reactions = _reactions();
    final ownId = widget.room.client.userID ?? '';

    // Check which emojis the current user has reacted with
    final myReactions = <String>{};
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

// ─────────────────────────────────────────────────────────────────────────────
// Emoji Picker
// ─────────────────────────────────────────────────────────────────────────────

const _kCategories = <_EmojiCategory>[
  _EmojiCategory(icon: '😀', label: 'Smileys', emojis: [
    '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇',
    '🥰','😍','🤩','😘','😗','☺️','😚','😙','🥲','😋','😛','😜','🤪',
    '😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒',
    '🙄','😬','🤥','😌','😔','😪','🤤','😴','😷','🤒','🤕','🤢','🤮',
    '🤧','🥵','🥶','🥴','😵','🤯','🤠','🥳','🥸','😎','🤓','🧐',
    '😕','😟','🙁','☹️','😮','😯','😲','😳','🥺','😦','😧','😨','😰',
    '😥','😢','😭','😱','😖','😣','😞','😓','😩','😫','🥱','😤','😡',
    '😠','🤬','😈','👿','💀','☠️','💩','🤡','👹','👺','👻','👽','👾','🤖',
  ]),
  _EmojiCategory(icon: '👍', label: 'Gestures', emojis: [
    '👋','🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙',
    '👈','👉','👆','🖕','👇','☝️','👍','👎','✊','👊','🤛','🤜','👏',
    '🙌','👐','🤲','🤝','🙏','✍️','💅','🤳','💪','🦾',
  ]),
  _EmojiCategory(icon: '👶', label: 'People', emojis: [
    '👶','🧒','👦','👧','🧑','👱','👨','🧔','👩','🧓','👴','👵',
    '🙍','🙎','🙅','🙆','💁','🙋','🧏','🙇','🤦','🤷',
    '👮','🕵️','💂','🥷','👷','🤴','👸','👳','👲','🧕','🤵','👰',
    '🤰','🤱','👼','🎅','🤶','🦸','🦹','🧙','🧝','🧛','🧟','🧞',
    '🧜','🧚','👫','👬','👭','💏','💑','👪',
  ]),
  _EmojiCategory(icon: '🐶', label: 'Animals', emojis: [
    '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮',
    '🐷','🐸','🐵','🐔','🐧','🐦','🐤','🦆','🦅','🦉','🦇','🐺',
    '🐴','🦄','🐝','🐛','🦋','🐌','🐞','🐜','🦟','🦗','🐢','🐍',
    '🦎','🐙','🦑','🐡','🐠','🐟','🐬','🐳','🦈','🐊','🐘','🦒',
    '🦓','🦏','🐪','🐫','🐃','🐄','🐎','🐖','🐏','🐑','🦙','🐐',
    '🦌','🐕','🐈','🐓','🦃','🦚','🦜','🦢','🦩','🕊️','🐇','🦝',
  ]),
  _EmojiCategory(icon: '🍎', label: 'Food', emojis: [
    '🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍒','🍑','🥭',
    '🍍','🥥','🥝','🍅','🍆','🥑','🥦','🥕','🌶️','🥔','🍠','🥐',
    '🍞','🥖','🧀','🥚','🍳','🥞','🧇','🥓','🥩','🍗','🍖','🌭',
    '🍔','🍟','🍕','🥪','🌮','🌯','🥗','🍝','🍜','🍲','🍛','🍣',
    '🍱','🥟','🍤','🍙','🍚','🍘','🍥','🧁','🍰','🎂','🍮','🍭',
    '🍬','🍫','🍿','🍩','🍪','🌰','🥜','🍯','☕','🍵','🍶','🍺',
    '🍻','🥂','🍷','🥃','🍸','🍹','🧃','🥤','🧋',
  ]),
  _EmojiCategory(icon: '⚽', label: 'Activity', emojis: [
    '⚽','🏀','🏈','⚾','🥎','🎾','🏐','🏉','🎱','🏓','🏸','🥊',
    '🥋','🎽','🛹','⛸️','🎿','🏆','🥇','🥈','🥉','🏅','🎖️','🎪',
    '🤹','🎭','🎨','🎬','🎤','🎧','🎼','🎹','🥁','🎸','🎺','🎷',
    '🎻','🎲','♟️','🎯','🎳','🎮','🎰','🧩',
  ]),
  _EmojiCategory(icon: '🌍', label: 'Travel', emojis: [
    '🚗','🚕','🚙','🚌','🏎️','🚓','🚑','🚒','🚐','🛻','🚚','🚛',
    '🚜','🏍️','🛵','🚲','✈️','🚁','🚀','🛸','⛵','🚤','🛥️','🚢',
    '🌍','🌎','🌏','🗺️','🏔️','🌋','🏕️','🏖️','🏜️','🏝️','🏟️','🏛️',
    '🏠','🏡','🏢','🏥','🏦','🏨','🏪','🏫','🏬','🏯','🏰','⛪',
    '🌁','🌃','🏙️','🌄','🌅','🌆','🌇','🌉','🎠','🎡','🎢',
  ]),
  _EmojiCategory(icon: '❤️', label: 'Symbols', emojis: [
    '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕',
    '💞','💓','💗','💖','💘','💝','💟','☮️','✌️','🕊️','🌈','✨',
    '⭐','🌟','💫','⚡','🔥','💥','❄️','🌊','🎉','🎊','🎈','🎁',
    '🎀','🏳️','🏴','🚩','🎌','🏁','💯','✅','❌','❓','❗','⚠️',
    '🔔','🔕','🔇','🔈','🔉','🔊','📣','📢','💬','💭','💤',
  ]),
];

class _EmojiCategory {
  final String icon;
  final String label;
  final List<String> emojis;
  const _EmojiCategory(
      {required this.icon, required this.label, required this.emojis});
}

class _EmojiPickerSheet extends StatefulWidget {
  final void Function(String) onPick;
  const _EmojiPickerSheet({required this.onPick});

  @override
  State<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<_EmojiPickerSheet> {
  int _selectedCategory = 0;
  final _searchCtrl = TextEditingController();
  List<String>? _searchResults;
  final _gridKey = GlobalKey();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    final all = _kCategories.expand((c) => c.emojis).toList();
    setState(() => _searchResults = all.where((e) => e.contains(trimmed)).toList());
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchResults != null;
    final displayEmojis = isSearching
        ? _searchResults!
        : _kCategories[_selectedCategory].emojis;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF13181F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            const SizedBox(height: 10),
            Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A4352),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E252F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A3341)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearch,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search…',
                    hintStyle: const TextStyle(
                        color: Color(0xFF5A6478), fontSize: 14),
                    prefixIcon: const Icon(Icons.search,
                        color: Color(0xFF5A6478), size: 18),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.close,
                          color: Color(0xFF5A6478), size: 16),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchResults = null);
                      },
                    )
                        : null,
                    border: InputBorder.none,
                    contentPadding:
                    const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Category tabs (hidden when searching)
            if (!isSearching)
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _kCategories.length,
                  itemBuilder: (context, i) {
                    final selected = _selectedCategory == i;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCategory = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF2E7DFF)
                              : const Color(0xFF1E252F),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_kCategories[i].icon}  ${_kCategories[i].label}',
                          style: TextStyle(
                            fontSize: 13,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF8B96A5),
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (!isSearching) const SizedBox(height: 6),

            // Emoji grid — fixed height so sheet doesn't grow forever
            SizedBox(
              height: 280,
              child: displayEmojis.isEmpty
                  ? const Center(
                child: Text('No results',
                    style: TextStyle(color: Color(0xFF5A6478))),
              )
                  : GridView.builder(
                key: ValueKey(_selectedCategory),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 0,
                  crossAxisSpacing: 0,
                  childAspectRatio: 1,
                ),
                itemCount: displayEmojis.length,
                itemBuilder: (context, i) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => widget.onPick(displayEmojis[i]),
                    child: Center(
                      child: Text(
                        displayEmojis[i],
                        style: const TextStyle(fontSize: 26),
                      ),
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