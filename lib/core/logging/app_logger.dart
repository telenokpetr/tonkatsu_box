import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../shared/constants/platform_features.dart';
import 'startup_error.dart';

const int _maxLogFileBytes = 2 * 1024 * 1024;

/// One line per record, with the error and stack trace on the lines after it.
String formatLogRecord(LogRecord record) {
  final StringBuffer out = StringBuffer(
    '${record.time.toIso8601String()} [${record.level.name}] '
    '${record.loggerName}: ${record.message}',
  );
  if (record.error != null) out.write('\n  error: ${record.error}');
  if (record.stackTrace != null) out.write('\n${record.stackTrace}');
  return out.toString();
}

/// Call once in `main()` before `runApp()`. Logs go through `dart:developer`
/// so they reach the `flutter run` console and the DevTools Logging tab.
abstract final class AppLogger {
  static final Logger _log = Logger('AppLogger');

  static void init() {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen(_onLogRecord);
    _openLogFile();
  }

  static IOSink? _sink;

  /// `%APPDATA%\Tonkatsu Box\Tonkatsu Box\logs	onkatsu_box.log`, rolled to
  /// `.old.log` past 2 MB; a log that cannot be opened must never stop startup.
  static void _openLogFile() {
    // flutter test must not write into the real log of the installed app.
    if (kIsWebBuild || Platform.environment.containsKey('FLUTTER_TEST')) return;
    final String? appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return;
    try {
      final Directory dir = Directory(
        p.join(appData, 'Tonkatsu Box', 'Tonkatsu Box', 'logs'),
      )..createSync(recursive: true);
      final File file = File(p.join(dir.path, 'tonkatsu_box.log'));
      if (file.existsSync() && file.lengthSync() > _maxLogFileBytes) {
        final File old = File(p.join(dir.path, 'tonkatsu_box.old.log'));
        if (old.existsSync()) old.deleteSync();
        file.renameSync(old.path);
      }
      _sink = file.openWrite(mode: FileMode.append);
      _sink?.writeln('--- start ${DateTime.now().toIso8601String()} ---');
    } on Exception {
      _sink = null;
    }
  }

  /// Catches unhandled Flutter and Dart errors; call once after [init].
  static void setupErrorHandlers() {
    // Widget tree errors (red screen).
    FlutterError.onError = (FlutterErrorDetails details) {
      _log.severe(
        'Flutter error: ${details.exceptionAsString()}',
        details.exception,
        details.stack,
      );
      FlutterError.presentError(details);
    };

    // Unhandled errors outside Flutter (Dart isolate).
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _log.severe('Unhandled platform error', error, stack);
      recordStartupError('platform', error, stack);
      return true;
    };
  }

  static void _onLogRecord(LogRecord record) {
    // Noisy FINE records from packages stay in the console only.
    if (record.level >= Level.INFO) _sink?.writeln(formatLogRecord(record));
    developer.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }
}
