import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import 'app_http_overrides.dart';

/// Desktop runs on the ffi engine; Android keeps the sqflite plugin factory.
void initPlatform() {
  HttpOverrides.global = AppHttpOverrides();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // Only the Windows and Android builds bundle libmpv; elsewhere Watch is off.
  if (Platform.isWindows || Platform.isAndroid) MediaKit.ensureInitialized();
}
