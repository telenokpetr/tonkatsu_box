import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:tonkatsu_box/core/logging/app_logger.dart';

void main() {
  group('formatLogRecord', () {
    test('puts time, level, logger and message on one line', () {
      final LogRecord record = LogRecord(
        Level.INFO,
        'hello',
        'Watch',
        null,
        null,
        null,
        null,
      );
      final String line = formatLogRecord(record);
      expect(line, contains('[INFO] Watch: hello'));
      expect(line, isNot(contains('\n')));
    });

    test('adds the error and stack trace on the following lines', () {
      final LogRecord record = LogRecord(
        Level.SEVERE,
        'boom',
        'Watch',
        StateError('bad'),
        StackTrace.fromString('#0 frame'),
      );
      final String text = formatLogRecord(record);
      expect(text, contains('error: Bad state: bad'));
      expect(text, contains('#0 frame'));
    });
  });

  group('AppLogger', () {
    group('init', () {
      test('should set уровень логирования ALL', () {
        AppLogger.init();

        expect(Logger.root.level, Level.ALL);
      });

      test('должен зарегистрировать listener на записи лога', () {
        AppLogger.init();

        Logger('test').info('test message');
      });
    });

    group('setupErrorHandlers', () {
      late FlutterExceptionHandler? originalOnError;
      late FlutterExceptionHandler? originalPresentError;

      setUp(() {
        originalOnError = FlutterError.onError;
        originalPresentError = FlutterError.presentError;
      });

      tearDown(() {
        FlutterError.onError = originalOnError;
        FlutterError.presentError = originalPresentError!;
      });

      test('should set FlutterError.onError', () {
        AppLogger.setupErrorHandlers();

        expect(FlutterError.onError, isNotNull);
      });

      test('FlutterError.onError должен логировать ошибку', () {
        AppLogger.init();
        AppLogger.setupErrorHandlers();

        // Suppress presentError so the test framework doesn't catch the exception.
        FlutterError.presentError = (FlutterErrorDetails details) {};

        final List<LogRecord> records = <LogRecord>[];
        Logger('AppLogger').onRecord.listen(records.add);

        final FlutterErrorDetails details = FlutterErrorDetails(
          exception: Exception('test error'),
          stack: StackTrace.current,
        );

        FlutterError.onError!(details);

        expect(records, isNotEmpty);
        expect(records.first.level, Level.SEVERE);
        expect(records.first.message, contains('Flutter error'));
      });
    });
  });
}
