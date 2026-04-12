import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';

class EmojiPickerSheet extends StatelessWidget {
  final void Function(String) onPick;
  final VoidCallback? onBackspacePressed;
  const EmojiPickerSheet({super.key, required this.onPick, this.onBackspacePressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: EmojiPicker(
          onEmojiSelected: (_, emoji) => onPick(emoji.emoji),
          onBackspacePressed: onBackspacePressed,
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
