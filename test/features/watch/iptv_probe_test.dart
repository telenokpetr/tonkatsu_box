import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tonkatsu_box/features/watch/iptv_probe.dart';

import '../../helpers/test_helpers.dart';

void main() {
  late MockDio dio;

  setUpAll(registerAllFallbacks);

  setUp(() => dio = MockDio());

  Response<ResponseBody> reply(int status) => Response<ResponseBody>(
    statusCode: status,
    requestOptions: RequestOptions(),
  );

  void stubGet(Future<Response<ResponseBody>> Function() answer) {
    when(
      () => dio.get<ResponseBody>(
        any(),
        cancelToken: any(named: 'cancelToken'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((_) => answer());
  }

  group('probeStream', () {
    test('a stream that answers is alive', () async {
      stubGet(() async => reply(200));
      expect(await probeStream(dio, 'http://h/a.m3u8'), isTrue);
    });

    test('a connection error or a timeout means dead', () async {
      stubGet(() async => throw DioException(requestOptions: RequestOptions()));
      expect(await probeStream(dio, 'http://h/a.m3u8'), isFalse);
    });

    test('only http links are probed', () async {
      expect(await probeStream(dio, 'udp://224.2.2.4:10000'), isFalse);
      verifyNever(
        () => dio.get<ResponseBody>(
          any(),
          cancelToken: any(named: 'cancelToken'),
          options: any(named: 'options'),
        ),
      );
    });

    test('asks for the first kilobyte only', () async {
      stubGet(() async => reply(206));
      await probeStream(dio, 'http://h/a.m3u8');
      final Options options =
          verify(
                () => dio.get<ResponseBody>(
                  any(),
                  cancelToken: any(named: 'cancelToken'),
                  options: captureAny(named: 'options'),
                ),
              ).captured.single
              as Options;
      expect(options.headers?['Range'], 'bytes=0-1023');
    });
  });

  group('IptvProbeState', () {
    test('finishes when every channel was checked', () {
      expect(
        const IptvProbeState(alive: <String>{}, done: 3, total: 3).finished,
        isTrue,
      );
      expect(
        const IptvProbeState(alive: <String>{}, done: 2, total: 3).finished,
        isFalse,
      );
    });
  });
}
