import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:maio/page/roompage.dart';
import 'package:maio/page/verificationpage.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'loginpage.dart';

class RoomListPage extends StatefulWidget {
  const RoomListPage({Key? key}) : super(key: key);

  @override
  _RoomListPageState createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  StreamSubscription? _verifSub;
  KeyVerification? _pendingRequest;

  @override
  void initState() {
    super.initState();
    _listenForVerificationRequests();
  }

  @override
  void dispose() {
    _verifSub?.cancel();
    super.dispose();
  }

  static String stripReplyFallback(String body) {
    if (!body.startsWith('> ')) return body;
    final lines = body.split('\n');
    int i = 0;
    while (i < lines.length && lines[i].startsWith('> ')) {
      i++;
    }
    // Skip the blank separator line.
    if (i < lines.length && lines[i].trim().isEmpty) i++;
    return lines.sublist(i).join('\n').trim();
  }

  String _getInsightText(Event event) {
    String newBody = stripReplyFallback(event.body);
    if (event.type != "m.room.message") {
      newBody = "Event";
    }
    return newBody;
  }

  void _listenForVerificationRequests() {
    final client = Provider.of<Client>(context, listen: false);
    _verifSub = client.onKeyVerificationRequest.stream.listen((request) {
      if (!mounted) return;
      setState(() => _pendingRequest = request);
    });
  }

  void _logout() async {
    final client = Provider.of<Client>(context, listen: false);
    await client.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  void _openVerification(Client client, {KeyVerification? request}) {
    setState(() => _pendingRequest = null);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VerificationPage(client: client, request: request),
    ));
  }

  void _join(Room room) async {
    if (room.membership != Membership.join) await room.join();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RoomPage(room: room)),
    );
  }

  Widget _buildAvatar(Uri? imageUri, Client client) {
    if (imageUri == null) {
      return const CircleAvatar(child: Icon(Icons.chat_bubble_outline));
    }
    return CachedNetworkImage(
      imageUrl: imageUri.toString(),
      httpHeaders: {
        'Authorization': 'Bearer ${client.accessToken}',
      },
      imageBuilder: (_, img) => CircleAvatar(backgroundImage: img),
      placeholder: (_, __) =>
      const CircleAvatar(child: Icon(Icons.chat_bubble_outline)),
      errorWidget: (_, __, ___) =>
      const CircleAvatar(child: Icon(Icons.chat_bubble_outline)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = Provider.of<Client>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        title: const Text('Chats',
            style: TextStyle(color: Color(0xFFF2F4F7))),
        actions: [
          // Verify button — opens self-verification
          IconButton(
            icon: const Icon(Icons.verified_user_outlined),
            tooltip: 'Verify device',
            color: const Color(0xFFF2F4F7),
            onPressed: () => _openVerification(client),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            color: const Color(0xFFF2F4F7),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Incoming verification request banner ──────────────────────
          if (_pendingRequest != null)
            GestureDetector(
              onTap: () => _openVerification(client, request: _pendingRequest),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                color: const Color(0xFF1B2D1F),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user,
                        color: Color(0xFF34C759), size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Incoming verification request — tap to verify',
                        style: TextStyle(
                            color: Color(0xFF34C759),
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: Color(0xFF34C759), size: 20),
                  ],
                ),
              ),
            ),

          // ── Room list ─────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder(
              stream: client.onSync.stream,
              builder: (context, _) => ListView.builder(
                itemCount: client.rooms.length,
                itemBuilder: (context, i) {
                  final room = client.rooms[i];
                  return ListTile(
                    leading: FutureBuilder<Uri?>(
                      future: room.avatar == null
                          ? Future.value(null)
                          : room.avatar!.getThumbnailUri(
                        client,
                        width: 56,
                        height: 56,
                      ),
                      builder: (context, snapshot) =>
                          _buildAvatar(snapshot.data, client),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.name.isEmpty
                                ? room.getLocalizedDisplayname()
                                : room.name,
                            style: const TextStyle(
                                color: Color(0xFFF2F4F7)),
                          ),
                        ),
                        if (room.notificationCount > 0)
                          Text(
                            room.notificationCount.toString(),
                            style: const TextStyle(
                                color: Color(0xFF4C8DF6)),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      room.lastEvent?.body == null ? 'No messages' : _getInsightText(room.lastEvent!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                      const TextStyle(color: Color(0xFF667085)),
                    ),
                    onTap: () => _join(room),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}