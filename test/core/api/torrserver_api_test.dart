import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tonkatsu_box/core/api/torrserver_api.dart';

import '../../helpers/test_helpers.dart';

void main() {
  late MockDio mockDio;
  late TorrServerApi sut;

  setUpAll(registerAllFallbacks);

  setUp(() {
    mockDio = MockDio();
    sut = TorrServerApi(
      baseUrl: '127.0.0.1:8090/',
      dio: mockDio,
      pollInterval: Duration.zero,
    );
  });

  Map<String, dynamic> torrentJson({
    String hash = 'abc123',
    List<Map<String, Object>>? files,
  }) => <String, dynamic>{
    'hash': hash,
    'title': 'Some Movie',
    'file_stats': ?files,
  };

  void stubPost(List<Map<String, dynamic>> responses, List<Object?> bodies) {
    int call = 0;
    when(
      () => mockDio.post<dynamic>(any(), data: any(named: 'data')),
    ).thenAnswer((Invocation inv) async {
      bodies.add(inv.namedArguments[#data]);
      final Map<String, dynamic> data =
          responses[call < responses.length ? call : responses.length - 1];
      call++;
      return Response<dynamic>(
        data: data,
        statusCode: 200,
        requestOptions: RequestOptions(),
      );
    });
  }

  const List<Map<String, Object>> twoFiles = <Map<String, Object>>[
    <String, Object>{'id': 1, 'path': 'Show/S01E01.mkv', 'length': 100},
    <String, Object>{'id': 2, 'path': 'Show/info.nfo', 'length': 1},
  ];

  group('TorrServerFile', () {
    test('name and extension come from the path', () {
      const TorrServerFile file = TorrServerFile(
        id: 1,
        path: 'Dir/Sub/Movie.MKV',
        length: 5,
      );
      expect(file.name, 'Movie.MKV');
      expect(file.extension, '.mkv');
      expect(file.isVideo, isTrue);
    });

    test('non-video extensions are not video', () {
      const TorrServerFile file = TorrServerFile(
        id: 2,
        path: 'readme.txt',
        length: 5,
      );
      expect(file.isVideo, isFalse);
    });
  });

  group('TorrServerTorrent.fromJson', () {
    test('parses file_stats and keeps only video in videoFiles', () {
      final TorrServerTorrent torrent = TorrServerTorrent.fromJson(
        torrentJson(files: twoFiles),
      );
      expect(torrent.hash, 'abc123');
      expect(torrent.files, hasLength(2));
      expect(torrent.videoFiles.map((TorrServerFile f) => f.id), <int>[1]);
    });

    test('no file_stats yet means an empty list', () {
      expect(TorrServerTorrent.fromJson(torrentJson()).files, isEmpty);
    });
  });

  group('addTorrent', () {
    test('posts the add action without saving to the DB', () async {
      final List<Object?> bodies = <Object?>[];
      stubPost(<Map<String, dynamic>>[torrentJson()], bodies);

      final TorrServerTorrent torrent = await sut.addTorrent(
        'magnet:?xt=urn:btih:abc',
        title: 'T',
      );

      expect(torrent.hash, 'abc123');
      final Map<String, dynamic> body = bodies.single! as Map<String, dynamic>;
      expect(body['action'], 'add');
      expect(body['link'], 'magnet:?xt=urn:btih:abc');
      expect(body['title'], 'T');
      expect(body['save_to_db'], isFalse);
      final String url =
          verify(
                () => mockDio.post<dynamic>(
                  captureAny(),
                  data: any(named: 'data'),
                ),
              ).captured.single
              as String;
      expect(url, 'http://127.0.0.1:8090/torrents');
    });

    test('throws when the URL is empty', () {
      final TorrServerApi unconfigured = TorrServerApi(
        baseUrl: '',
        dio: mockDio,
      );
      expect(
        () => unconfigured.addTorrent('magnet:?x'),
        throwsA(isA<TorrServerApiException>()),
      );
    });

    test('wraps network errors', () async {
      when(
        () => mockDio.post<dynamic>(any(), data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(),
          message: 'connection refused',
        ),
      );

      await expectLater(
        sut.addTorrent('magnet:?x'),
        throwsA(
          isA<TorrServerApiException>().having(
            (TorrServerApiException e) => e.message,
            'message',
            'connection refused',
          ),
        ),
      );
    });
  });

  group('waitForFiles', () {
    test('polls until file_stats shows up', () async {
      final List<Object?> bodies = <Object?>[];
      stubPost(<Map<String, dynamic>>[
        torrentJson(),
        torrentJson(),
        torrentJson(files: twoFiles),
      ], bodies);

      final TorrServerTorrent torrent = await sut.waitForFiles('abc123');

      expect(torrent.files, hasLength(2));
      expect(bodies, hasLength(3));
      expect(
        bodies.every(
          (Object? b) => (b! as Map<String, dynamic>)['action'] == 'get',
        ),
        isTrue,
      );
    });

    test('gives up after the timeout', () async {
      stubPost(<Map<String, dynamic>>[torrentJson()], <Object?>[]);

      await expectLater(
        sut.waitForFiles('abc123', timeout: Duration.zero),
        throwsA(isA<TorrServerApiException>()),
      );
    });
  });

  group('streamUrl', () {
    test('encodes the file name and carries hash and 1-based index', () {
      final TorrServerTorrent torrent = TorrServerTorrent.fromJson(
        torrentJson(hash: 'h1', files: twoFiles),
      );
      const TorrServerFile file = TorrServerFile(
        id: 3,
        path: 'A/My Movie #1.mkv',
        length: 1,
      );

      expect(
        sut.streamUrl(torrent, file),
        'http://127.0.0.1:8090/stream/My%20Movie%20%231.mkv'
        '?link=h1&index=3&play',
      );
    });
  });

  group('echo', () {
    test('returns the trimmed version text', () async {
      when(
        () => mockDio.get<String>(any(), options: any(named: 'options')),
      ).thenAnswer(
        (_) async => Response<String>(
          data: 'MatriX.Docker\n',
          statusCode: 200,
          requestOptions: RequestOptions(),
        ),
      );

      expect(await sut.echo(), 'MatriX.Docker');
    });
  });
}
