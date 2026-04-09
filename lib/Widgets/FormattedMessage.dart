import 'package:flutter/material.dart';

class FormattedMessage extends StatelessWidget {
  final String text;

  const FormattedMessage({
    super.key,
    required this.text
  });

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      color: Colors.white,
      fontSize: 15,
      height: 1.25,
    );

    return SelectableText.rich(
      TextSpan(
        style: baseStyle,
        children: _buildMessageSpans(text, baseStyle),
      ),
    );
  }

  List<InlineSpan> _buildMessageSpans(String text, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    final regex = RegExp(
      r'(\*\*.*?\*\*|__.*?__|~~.*?~~|`.*?`)',
      multiLine: true,
    );

    int currentIndex = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(
          text: text.substring(currentIndex, match.start),
          style: baseStyle,
        ));
      }

      final token = match.group(0)!;
      if (token.startsWith('**') && token.endsWith('**')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: baseStyle.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (token.startsWith('__') && token.endsWith('__')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFFB7C4D6),
            decorationThickness: 1.1,
          ),
        ));
      } else if (token.startsWith('~~') && token.endsWith('~~')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        ));
      } else if (token.startsWith('`') && token.endsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: const Color(0x223A4352),
          ),
        ));
      } else {
        spans.add(TextSpan(text: token, style: baseStyle));
      }

      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentIndex),
        style: baseStyle,
      ));
    }

    return spans;
  }
}
