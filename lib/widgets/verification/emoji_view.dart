import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:maio/widgets/verification/page_shell.dart';
import 'package:maio/widgets/verification/section_body.dart';
import 'package:maio/widgets/verification/section_title.dart';
import 'package:matrix/encryption/utils/key_verification.dart';

import '../../main.dart';
import 'emoji_cell.dart';

class EmojiView extends StatelessWidget {
  final List<KeyVerificationEmoji> emojis;
  final VoidCallback onConfirm;
  final VoidCallback onDeny;

  const EmojiView({
    required this.emojis,
    required this.onConfirm,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    final crossCount = isWide ? 4 : 4;

    return PageShell(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.blue.withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.compare_arrows_rounded,
                  color: AppTheme.blue, size: 14),
              SizedBox(width: 6),
              Text(
                'Compare on both devices',
                style: TextStyle(
                  color: AppTheme.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionTitle('Do the emojis match?'),
        const SizedBox(height: 8),
        const SectionBody(
            'Check that these emojis appear in the same order on your other device.'),
        const SizedBox(height: 28),
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.9,
          ),
          itemCount: emojis.length,
          itemBuilder: (_, i) => EmojiCell(emoji: emojis[i]),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onDeny,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text("No match"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.red,
                    side:
                    BorderSide(color: AppTheme.red.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text("They match"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}