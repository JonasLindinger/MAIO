import 'package:flutter/cupertino.dart';

class PageShell extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;

  const PageShell({
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}