import 'package:flutter/material.dart';
import 'package:maio/widgets/verification/page_shell.dart';
import 'package:maio/widgets/verification/primary_button.dart';
import 'package:maio/widgets/verification/section_body.dart';
import 'package:maio/widgets/verification/section_title.dart';
import 'package:maio/widgets/verification/status_icon.dart';
import '../../main.dart';
import 'info_card.dart';

class IdleView extends StatelessWidget {
  final String? error;
  final VoidCallback onStart;

  const IdleView({required this.error, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return PageShell(
      children: [
        const StatusIcon(
          icon: Icons.verified_user_rounded,
          color: AppTheme.blue,
          bgColor: Color(0xFF0D1829),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Verify this device'),
        const SizedBox(height: 12),
        const SectionBody(
          'Verify your identity so others can trust your messages. '
              'Open Element or another Matrix client on a verified device '
              'and accept the incoming request.',
        ),
        const SizedBox(height: 24),
        InfoCard(
          icon: Icons.devices_rounded,
          color: AppTheme.blue,
          text:
          'Keep both devices unlocked and in the foreground during verification.',
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          InfoCard(
            icon: Icons.warning_amber_rounded,
            color: AppTheme.red,
            text: error!,
          ),
        ],
        const SizedBox(height: 28),
        PrimaryButton(
          label: 'Start Verification',
          icon: Icons.shield_rounded,
          onPressed: onStart,
        ),
      ],
    );
  }
}