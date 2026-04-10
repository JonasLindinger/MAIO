import 'package:flutter/material.dart';
import 'package:maio/widgets/verification/page_shell.dart';
import 'package:maio/widgets/verification/primary_button.dart';
import 'package:maio/widgets/verification/section_body.dart';
import 'package:maio/widgets/verification/section_title.dart';
import 'package:maio/widgets/verification/status_icon.dart';

import '../../main.dart';
import 'info_card.dart';

class DoneView extends StatelessWidget {
  final VoidCallback onClose;

  const DoneView({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return PageShell(
      children: [
        const StatusIcon(
          icon: Icons.verified_rounded,
          color: AppTheme.green,
          bgColor: Color(0xFF0A1F12),
          size: 64,
        ),
        const SizedBox(height: 24),
        const SectionTitle('Verification complete'),
        const SizedBox(height: 12),
        const SectionBody(
          'This device is now trusted. Your messages will show a verified '
              'badge in other Matrix clients.',
        ),
        const SizedBox(height: 24),
        InfoCard(
          icon: Icons.check_circle_outline_rounded,
          color: AppTheme.green,
          text: 'The unverified badge will disappear from your messages.',
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          label: 'Done',
          onPressed: onClose,
          color: AppTheme.green,
        ),
      ],
    );
  }
}