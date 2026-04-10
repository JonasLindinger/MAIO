import 'package:flutter/material.dart';

// Compiled once at app startup — never re-instantiated
final _kMarkdownRegex = RegExp(
  r'(\*\*.*?\*\*|__.*?__|~~.*?~~|`.*?`)',
  multiLine: true,
);

const _kBase = TextStyle(color: Colors.white, fontSize: 15, height: 1.25);

// Global parsed-span cache. Key = message text string.
// LRU eviction isn't needed for a chat app — the set of unique messages
// is bounded by the timeline size, which Matrix SDKs cap anyway.
final Map<String, List<InlineSpan>> _kSpanCache = {};

class FormattedMessage extends StatelessWidget {
  final String text;
  const FormattedMessage({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    // Text.rich instead of SelectableText.rich — no gesture arena overhead
    return Text.rich(
      TextSpan(
        style: _kBase,
        children: _kSpanCache.putIfAbsent(text, () => _parse(text)),
      ),
    );
  }
}

List<InlineSpan> _parse(String text) {
  final spans = <InlineSpan>[];
  int cursor = 0;

  for (final m in _kMarkdownRegex.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start)));
    }

    final token = m.group(0)!;

    if (token.startsWith('**')) {
      spans.add(TextSpan(
        text: token.substring(2, token.length - 2),
        style: _kBase.copyWith(fontWeight: FontWeight.w700),
      ));
    } else if (token.startsWith('__')) {
      spans.add(TextSpan(
        text: token.substring(2, token.length - 2),
        style: _kBase.copyWith(
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xFFB7C4D6),
          decorationThickness: 1.1,
        ),
      ));
    } else if (token.startsWith('~~')) {
      spans.add(TextSpan(
        text: token.substring(2, token.length - 2),
        style: _kBase.copyWith(decoration: TextDecoration.lineThrough),
      ));
    } else if (token.startsWith('`')) {
      spans.add(TextSpan(
        text: token.substring(1, token.length - 1),
        style: _kBase.copyWith(
          fontFamily: 'monospace',
          backgroundColor: const Color(0x223A4352),
        ),
      ));
    } else {
      spans.add(TextSpan(text: token));
    }

    cursor = m.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }

  return spans;
}