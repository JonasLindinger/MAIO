import 'package:flutter/material.dart';
import 'package:maio/page/roompage.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import 'loginpage.dart';

class RoomListPage extends StatefulWidget {
  const RoomListPage({Key? key}) : super(key: key);

  @override
  _RoomListPageState createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  void _logout() async {
    final client = Provider.of<Client>(context, listen: false);
    await client.logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  void _join(Room room) async {
    if (room.membership != Membership.join) {
      await room.join();
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomPage(room: room),
      ),
    );
  }

  Widget _buildAvatar({
    required Uri? imageUri,
    required Client client,
    required IconData fallbackIcon,
  }) {
    if (imageUri == null) {
      return CircleAvatar(
        child: Icon(fallbackIcon),
      );
    }

    return CircleAvatar(
      foregroundImage: NetworkImage(
        imageUri.toString(),
        headers: {
          'Authorization': 'Bearer ${client.accessToken}',
        },
      ),
      onForegroundImageError: (_, __) {},
      child: Icon(fallbackIcon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = Provider.of<Client>(context, listen: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: StreamBuilder(
        stream: client.onSync.stream,
        builder: (context, _) => ListView.builder(
          itemCount: client.rooms.length,
          itemBuilder: (context, i) => ListTile(
            leading: FutureBuilder<Uri?>(
              future: client.rooms[i].avatar == null
                  ? Future.value(null)
                  : client.rooms[i].avatar!.getThumbnailUri(
                client,
                width: 56,
                height: 56,
              ),
              builder: (context, snapshot) {
                final uri = snapshot.data;

                if (uri == null) {
                  return const CircleAvatar(
                    child: Icon(Icons.chat_bubble_outline),
                  );
                }

                return CircleAvatar(
                  foregroundImage: NetworkImage(
                    uri.toString(),
                    headers: {
                      'Authorization': 'Bearer ${client.accessToken}',
                    },
                  ),
                  onForegroundImageError: (_, __) {},
                  child: const Icon(Icons.chat_bubble_outline),
                );
              },
            ),
            title: Row(
              children: [
                Expanded(child: Text(client.rooms[i].displayname)),
                if (client.rooms[i].notificationCount > 0)
                  Material(
                    borderRadius: BorderRadius.circular(99),
                    color: Colors.red,
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: Text(client.rooms[i].notificationCount.toString()),
                    ),
                  )
              ],
            ),
            subtitle: Text(
              client.rooms[i].lastEvent?.body ?? 'No messages',
              maxLines: 1,
            ),
            onTap: () => _join(client.rooms[i]),
          ),
        ),
      ),
    );
  }
}