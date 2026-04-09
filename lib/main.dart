import 'package:flutter/material.dart';
import 'package:maio/page/loginpage.dart';
import 'package:maio/page/roomlistpage.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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
    );
  }
}