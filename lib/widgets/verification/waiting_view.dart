import 'package:flutter/material.dart';
import 'package:maio/widgets/verification/page_shell.dart';
import 'package:maio/widgets/verification/section_body.dart';
import 'package:maio/widgets/verification/section_title.dart';

import '../../main.dart';

class WaitingView extends StatelessWidget {
  const WaitingView();

  @override
  Widget build(BuildContext context) {
    return PageShell(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppTheme.blue.withOpacity(0.15), width: 1),
              ),
            ),
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                color: AppTheme.blue,
                strokeWidth: 2,
              ),
            ),
            const Icon(Icons.smartphone_rounded,
                color: AppTheme.blue, size: 20),
          ],
        ),
        const SizedBox(height: 28),
        const SectionTitle('Waiting for response'),
        const SizedBox(height: 12),
        const SectionBody(
          'Accept the verification request on your other device to continue.',
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.blue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Request sent',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}