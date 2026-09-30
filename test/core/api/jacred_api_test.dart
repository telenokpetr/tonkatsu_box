import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tonkatsu_box/core/api/jacred_api.dart';

import '../../helpers/test_helpers.dart';

void main() {
  late MockDio mockDio;
  late JacRedApi sut;

  setUpAll(registerAllFallbacks);

  setUp(() {
    mockDio = MockDio();
    sut = JacRedApi(baseUrl: '192.168.1.5:9117/', apiKey: 'k', dio: mockDio);
  });

  Response<dynamic> jsonResponse(Object? data) => Response<dynamic>(
    data: data,
    statusCode: 200,
    requestOptions: RequestOptions(),
  );

  Map<String, dynamic> row({
    String title = 'Movie',
    String? magnet = 'magnet:?xt=urn:btih:abc',
    int seeders = 1,
  }) => <String, dynamic>{
    'Title': title,
    'MagnetUri': magnet,
    'Size': 1024,
    'Seeders': seeders,
    'Peers': 2,
    'Tracker': 'rutor',
    'PublishDate': '2026-07-17T00:56:00',
    'languages': <String>['rus', 'eng'],
    'info': <String, dynamic>{'quality': 1080},
  };

  void stubGet(Object? data) {
    when(
      () => mockDio.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => jsonResponse(data));
  }

  group('JacRedTorrent.fromJson', () {
    test('reads the Jackett fields JacRed sends', () {
      final JacRedTorrent t = JacRedTorrent.fromJson(row(title: 'The Matrix'));
      expect(t.title, 'The Matrix');
      expect(t.sizeBytes, 1024);
      expect(t.seeders, 1);
      expect(t.peers, 2);
      expect(t.tracker, 'rutor');
      expect(t.quality, 1080);
      expect(t.languages, <String>['rus', 'eng']);
      expect(t.publishedAt, DateTime(2026, 7, 17, 0, 56));
    });

    test('tolerates missing fields', () {
      final JacRedTorrent t = JacRedTorrent.fromJson(<String, dynamic>{});
      expect(t.title, isEmpty);
      expect(t.magnet, isEmpty);
      expect(t.sizeBytes, 0);
      expect(t.quality, isNull);
      expect(t.languages, isEmpty);
      expect(t.publishedAt, isNull);
    });

    test('quality 0 becomes null', () {
      final JacRedTorrent t = JacRedTorrent.fromJson(<String, dynamic>{
        'info': <String, dynamic>{'quality': 0},
      });
      expect(t.quality, isNull);
    });
  });

  group('search', () {
    test('throws when the URL is empty', () {
      final JacRedApi unconfigured = JacRedApi(baseUrl: '', dio: mockDio);
      expect(
        () => unconfigured.search(title: 'x'),
        throwsA(isA<JacRedApiException>()),
      );
    });

    test('sends the card query to the normalized URL', () async {
      stubGet(<String, dynamic>{'Results': <dynamic>[]});

      await sut.search(
        title: 'Matrix RU',
        originalTitle: 'The Matrix',
        year: 1999,
      );

      final VerificationResult call = verify(
        () => mockDio.get<dynamic>(
          captureAny(),
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      );
      expect(
        call.captured[0],
        'http://192.168.1.5:9117/api/v2.0/indexers/all/results',
      );
      final Map<String, dynamic> query =
          call.captured[1] as Map<String, dynamic>;
      expect(query['title'], 'Matrix RU');
      expect(query['title_original'], 'The Matrix');
      expect(query['year'], 1999);
      expect(query['is_serial'], 1);
      expect(query['apikey'], 'k');
    });

    test('marks a series with is_serial 2 and omits empty optionals', () async {
      stubGet(<String, dynamic>{'Results': <dynamic>[]});
      final JacRedApi keyless = JacRedApi(baseUrl: 'h', dio: mockDio);

      await keyless.search(title: 'Show', isSerial: true);

      final VerificationResult call = verify(
        () => mockDio.get<dynamic>(
          any(),
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      );
      final Map<String, dynamic> query =
          call.captured[0] as Map<String, dynamic>;
      expect(query['is_serial'], 2);
      expect(query.containsKey('apikey'), isFalse);
      expect(query.containsKey('year'), isFalse);
      expect(query.containsKey('title_original'), isFalse);
    });

    test('sorts by seeders and drops rows without a magnet', () async {
      stubGet(<String, dynamic>{
        'Results': <dynamic>[
          row(title: 'low', seeders: 3),
          row(title: 'nomagnet', magnet: null, seeders: 99),
          row(title: 'high', seeders: 50),
        ],
      });

      final List<JacRedTorrent> result = await sut.search(title: 'x');

      expect(result.map((JacRedTorrent t) => t.title), <String>['high', 'low']);
    });

    test('a body without Results is an empty list', () async {
      stubGet(<String, dynamic>{'jacred': true});
      expect(await sut.search(title: 'x'), isEmpty);
    });

    test('a non-object body throws', () async {
      stubGet('<html>');
      expect(() => sut.search(title: 'x'), throwsA(isA<JacRedApiException>()));
    });

    test('maps 401 to an API key error', () async {
      when(
        () => mockDio.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(),
          response: Response<dynamic>(
            statusCode: 401,
            requestOptions: RequestOptions(),
          ),
        ),
      );

      await expectLater(
        sut.search(title: 'x'),
        throwsA(
          isA<JacRedApiException>()
              .having((JacRedApiException e) => e.statusCode, 'status', 401)
              .having(
                (JacRedApiException e) => e.message,
                'message',
                contains('API key'),
              ),
        ),
      );
    });
  });

  group('ping', () {
    test('true when the server identifies as JacRed', () async {
      stubGet(<String, dynamic>{'jacred': true});
      expect(await sut.ping(), isTrue);
    });

    test('false for some other JSON server', () async {
      stubGet(<String, dynamic>{'ok': 1});
      expect(await sut.ping(), isFalse);
    });

    test('false without a URL, no request made', () async {
      final JacRedApi unconfigured = JacRedApi(baseUrl: '', dio: mockDio);
      expect(await unconfigured.ping(), isFalse);
      verifyNever(
        () => mockDio.get<dynamic>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      );
    });
  });
}
