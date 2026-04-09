import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

class RoomPage extends StatefulWidget {
  final Room room;
  const RoomPage({required this.room, Key? key}) : super(key: key);

  @override
  _RoomPageState createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  late final Future<Timeline> _timelineFuture;
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  int _count = 0;

  @override
  void initState() {
    _timelineFuture = widget.room.getTimeline(onChange: (i) {
      print('on change! $i');
      _listKey.currentState?.setState(() {});
    }, onInsert: (i) {
      print('on insert! $i');
      _listKey.currentState?.insertItem(i);
      _count++;
    }, onRemove: (i) {
      print('On remove $i');
      _count--;
      _listKey.currentState?.removeItem(i, (_, __) => const ListTile());
    }, onUpdate: () {
      print('On update');
    });

    super.initState();
  }

  final TextEditingController _sendController = TextEditingController();

  void _send() {
    widget.room.sendTextEvent(_sendController.text.trim());
    _sendController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.room.displayname),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<Timeline>(
                future: _timelineFuture,
                builder: (context, snapshot) {
                  final timeline = snapshot.data;
                  if (timeline == null) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(),
                    );
                  }
                  _count = timeline.events.length;

                  return Column(
                    children: [
                      Center(
                        child: TextButton(
                            onPressed: timeline.requestHistory,
                            child: const Text('Load more...')),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: AnimatedList(
                          key: _listKey,
                          reverse: true,
                          initialItemCount: timeline.events.length,
                          itemBuilder: (context, i, animation) => timeline
                              .events[i].relationshipEventId !=
                              null
                              ? Container()
                              : ScaleTransition(
                            scale: animation,
                            child: Opacity(
                              opacity: timeline.events[i].status.isSent
                                  ? 1
                                  : 0.5,
                              child: ListTile(
                                leading: FutureBuilder<Uri?>(
                                  future: timeline.events[i].senderFromMemoryOrFallback.avatarUrl == null
                                      ? Future.value(null)
                                      : timeline.events[i].senderFromMemoryOrFallback.avatarUrl!.getThumbnailUri(
                                    widget.room.client,
                                    width: 56,
                                    height: 56,
                                  ),
                                  builder: (context, snapshot) {
                                    final uri = snapshot.data;

                                    if (uri == null) {
                                      return const CircleAvatar(
                                        child: Icon(Icons.person_outline),
                                      );
                                    }

                                    return CircleAvatar(
                                      foregroundImage: NetworkImage(
                                        uri.toString(),
                                        headers: {
                                          'Authorization': 'Bearer ${widget.room.client.accessToken}',
                                        },
                                      ),
                                      onForegroundImageError: (_, __) {},
                                      child: const Icon(Icons.person_outline),
                                    );
                                  },
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(timeline
                                          .events[i].senderFromMemoryOrFallback
                                          .calcDisplayname()),
                                    ),
                                    Text(
                                      timeline.events[i].originServerTs
                                          .toIso8601String(),
                                      style:
                                      const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ),
                                subtitle: Text(timeline.events[i]
                                    .getDisplayEvent(timeline)
                                    .body),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                      child: TextField(
                        controller: _sendController,
                        decoration: const InputDecoration(
                          hintText: 'Send message',
                        ),
                      )),
                  IconButton(
                    icon: const Icon(Icons.send_outlined),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}