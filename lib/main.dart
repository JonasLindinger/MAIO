import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:maio/page/loginpage.dart';
import 'package:maio/page/roomlistpage.dart';
import 'package:maio/utils/notification_manager.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await vodozemac.init();
  await NotificationManager.initialize();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final dbDirectory = await getApplicationSupportDirectory();
  final dbPath = '${dbDirectory.path}/database.sqlite';

  final client = Client(
    'Matrix Example Chat',
    verificationMethods: {
      KeyVerificationMethod.emoji, // explicitly enable emoji/SAS
    },
    database: await MatrixSdkDatabase.init(
      "Database",
      database: await databaseFactory.openDatabase(dbPath),
    ),
  );

  await client.init();

  client.onTimelineEvent.stream.listen((Event event) {
    if (event.status != EventStatus.sent && event.status != EventStatus.synced) return;
    if (event.type != EventTypes.Message) return;
    final roomId = event.roomId;
    if (roomId == null) return;
    final room = client.getRoomById(roomId);
    if (room != null) {
      NotificationManager.showNotification(event, room);
    }
  });

  runApp(MaioClient(client: client));
}

// ── Theme ────────────────────────────────────────────────────────────────────

class AppTheme {
  static const bg = Color(0xFF0C0F14);
  static const surface = Color(0xFF131820);
  static const surfaceRaised = Color(0xFF1A2030);
  static const border = Color(0xFF1E2736);
  static const borderLight = Color(0xFF2A3548);
  static const blue = Color(0xFF4C8DF6);
  static const green = Color(0xFF34C759);
  static const red = Color(0xFFFF453A);
  static const textPrimary = Color(0xFFEDF1F7);
  static const textSecondary = Color(0xFF8A95A8);
  static const textMuted = Color(0xFF4A5568);
}

class MaioClient extends StatelessWidget {
  final Client client;
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const MaioClient({required this.client, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix Client',
      navigatorKey: navigatorKey,
      builder: (context, child) => Provider<Client>(
        create: (context) => client,
        child: child,
      ),
      home: client.isLogged() ? const RoomListPage() : const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
