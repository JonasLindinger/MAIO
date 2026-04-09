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
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        title: const Text(
          'Chats',
          style: TextStyle(
            color: Color(0xFFF2F4F7)
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            style: const ButtonStyle(
              foregroundColor: WidgetStateProperty<Color>.fromMap(<WidgetStatesConstraint, Color>{
                WidgetState.any: Color(0xFFF2F4F7),
              }),
            ),
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
                final Uri? uri = snapshot.data;

                return _buildAvatar(
                  imageUri: uri,
                  client: client,
                  fallbackIcon: Icons.chat_bubble_outline
                );
              },
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    client.rooms[i].name.isEmpty ? client.rooms[i].getLocalizedDisplayname() : client.rooms[i].name,
                    style: const TextStyle(
                      color: Color(0xFFF2F4F7)
                    ),
                  ),
                ),
                if (client.rooms[i].notificationCount > 0)
                  /*
                  // Dot
                  Material(
                    borderRadius: BorderRadius.circular(99),
                    color: const Color(0xFF4C8DF6),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                    ),
                  )
                  */

                  // Number
                  Text(
                    client.rooms[i].notificationCount.toString(),
                    style: const TextStyle(
                      color: Color(0xFF4C8DF6)
                    ),
                  )

                  /*
                  // Number with bg dot
                  Material(
                    borderRadius: BorderRadius.circular(99),
                    color: const Color(0xFF4C8DF6),
                    child: Padding(
                      padding: const EdgeInsets.all(2.0),
                      child: Text(client.rooms[i].notificationCount.toString()),
                    ),
                  )
                   */
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