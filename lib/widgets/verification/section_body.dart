import 'package:flutter/material.dart';
import '../../main.dart';

class SectionBody extends StatelessWidget {
  final String text;

  const SectionBody(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 14,
        height: 1.6,
      ),
    );
  }
}