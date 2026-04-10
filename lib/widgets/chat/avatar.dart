import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class AvatarWidget extends StatefulWidget {
  final Event event;
  final Future<String?> Function(Event) resolveAvatarUrl;

  const AvatarWidget({required this.event, required this.resolveAvatarUrl});

  @override
  State<AvatarWidget> createState() => _AvatarWidgetState();
}

class _AvatarWidgetState extends State<AvatarWidget> {
  String? _url;
  bool _resolved = false;

  static const _placeholder = CircleAvatar(
    radius: 18,
    backgroundColor: Color(0xFF2A3441),
    child: Icon(Icons.person_outline, size: 18, color: Colors.white70),
  );

  @override
  void initState() {
    super.initState();
    widget.resolveAvatarUrl(widget.event).then((url) {
      if (mounted) setState(() { _url = url; _resolved = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved || _url == null || _url!.isEmpty) return _placeholder;

    return CachedNetworkImage(
      imageUrl: _url!,
      memCacheWidth: 72,
      memCacheHeight: 72,
      imageBuilder: (_, img) => CircleAvatar(
        radius: 18,
        backgroundImage: img,
        backgroundColor: const Color(0xFF2A3441),
      ),
      placeholder: (_, __) => _placeholder,
      errorWidget: (_, __, ___) => _placeholder,
      width: 36,
      height: 36,
    );
  }
}