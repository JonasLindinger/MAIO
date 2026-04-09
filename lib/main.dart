import 'dart:io';
import 'package:flutter/material.dart';
import 'package:maio/page/loginpage.dart';
import 'package:maio/page/roomlistpage.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Only use FFI on desktop
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final dbDirectory = await getApplicationSupportDirectory();
  final dbPath = '${dbDirectory.path}/database.sqlite';

  final client = Client(
    'Matrix Example Chat',
    database: await MatrixSdkDatabase.init(
      "Database",
      database: await databaseFactory.openDatabase(dbPath),
    ),
  );

  await client.init();

  runApp(MaioClient(client: client));
}

// Colors:
// Background: const Color(0xFF0B0F14)
// Accent: const Color(0xFF4C8DF6)
// Text: Color(0xFFF2F4F7)
// Subtext: Color(0xFF98A2B3)
// SubSubtext: Color(0xFF667085)

class MaioClient extends StatelessWidget {
  final Client client;
  const MaioClient({required this.client, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix Client',
      builder: (context, child) => Provider<Client>(
        create: (context) => client,
        child: child,
      ),
      home: client.isLogged() ? const RoomListPage() : const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}