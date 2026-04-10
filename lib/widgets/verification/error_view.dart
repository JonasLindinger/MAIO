import 'package:flutter/material.dart';
import 'package:maio/widgets/verification/page_shell.dart';
import 'package:maio/widgets/verification/primary_button.dart';
import 'package:maio/widgets/verification/secondary_button.dart';
import 'package:maio/widgets/verification/section_title.dart';
import 'package:maio/widgets/verification/status_icon.dart';

import '../../main.dart';
import 'info_card.dart';

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const ErrorView({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return PageShell(
      children: [
        const StatusIcon(
          icon: Icons.error_outline_rounded,
          color: AppTheme.red,
          bgColor: Color(0xFF1F0A0A),
        ),
        const SizedBox(height: 24),
        const SectionTitle('Verification failed'),
        const SizedBox(height: 12),
        InfoCard(
          icon: Icons.info_outline_rounded,
          color: AppTheme.red,
          text: message,
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: onRetry,
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Cancel',
          onPressed: onClose,
        ),
      ],
    );
  }
}