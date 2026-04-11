import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:maio/main.dart';
import 'package:maio/page/roompage.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

class NotificationManager {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static String? currentRoomId;

  static Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
      linux: initializationSettingsLinux,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final roomId = response.payload;
        if (roomId == null) return;
        
        final context = MaioClient.navigatorKey.currentContext;
        if (context == null) return;
        
        final client = Provider.of<Client>(context, listen: false);
        final room = client.getRoomById(roomId);
        if (room == null) return;
        
        MaioClient.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => RoomPage(room: room)),
        );
      },
    );
  }

  static Future<void> showNotification(Event event, Room room) async {
    if (event.senderId == room.client.userID) return;
    if (event.type != EventTypes.Message) return;
    if (room.id == currentRoomId) return;

    // Check if event is too old (e.g., from initial sync or catching up)
    if (DateTime.now().difference(event.originServerTs).inMinutes > 5) return;

    final String? body = event.content['body'] as String?;
    if (body == null) return;

    final String senderName = event.senderFromMemoryOrFallback.displayName ?? event.senderId ?? 'Unknown';
    final String roomName = room.getLocalizedDisplayname();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'maio_messages',
      'Messages',
      channelDescription: 'Notifications for new messages',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
    );

    await _notificationsPlugin.show(
      id: event.eventId.hashCode,
      title: senderName == roomName ? senderName : '$senderName in $roomName',
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: room.id,
    );
  }
}
