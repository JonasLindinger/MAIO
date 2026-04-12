import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class AvatarWidget extends StatefulWidget {
  final Event event;
  final Future<String?> Function(Event) resolveAvatarUrl;

  const AvatarWidget({super.key, required this.event, required this.resolveAvatarUrl});

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

class RoomAvatar extends StatefulWidget {
  final Room room;
  final Client client;
  final double radius;

  const RoomAvatar({super.key, required this.room, required this.client, this.radius = 20});

  @override
  State<RoomAvatar> createState() => _RoomAvatarState();
}

class _RoomAvatarState extends State<RoomAvatar> {
  Uri? _avatarUri;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolveAvatar();
  }

  @override
  void didUpdateWidget(RoomAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.avatar != widget.room.avatar) {
      _resolveAvatar();
    }
  }

  void _resolveAvatar() async {
    if (widget.room.avatar == null) {
      if (mounted) setState(() { _avatarUri = null; _resolved = true; });
      return;
    }
    try {
      final uri = await widget.room.avatar!.getThumbnailUri(
        widget.client,
        width: (widget.radius * 2.8).toInt(),
        height: (widget.radius * 2.8).toInt(),
      );
      if (mounted) setState(() { _avatarUri = uri; _resolved = true; });
    } catch (_) {
      if (mounted) setState(() { _resolved = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = CircleAvatar(
      radius: widget.radius,
      backgroundColor: const Color(0xFF1C2430),
      child: Icon(Icons.chat_bubble_outline, size: widget.radius, color: const Color(0xFF667085)),
    );

    if (!_resolved || _avatarUri == null) {
      return placeholder;
    }
    return CachedNetworkImage(
      imageUrl: _avatarUri.toString(),
      httpHeaders: {
        'Authorization': 'Bearer ${widget.client.accessToken}',
      },
      imageBuilder: (_, img) => CircleAvatar(radius: widget.radius, backgroundImage: img),
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
    );
  }
}