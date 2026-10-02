import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tonkatsu_box/core/api/twitch_api.dart';

import '../../helpers/test_helpers.dart';

void main() {
  late MockDio dio;

  setUpAll(registerAllFallbacks);

  setUp(() => dio = MockDio());

  Response<dynamic> reply(Object? data, {int status = 200}) =>
      Response<dynamic>(
        data: data,
        statusCode: status,
        requestOptions: RequestOptions(),
      );

  Map<String, dynamic> row(
    String login, {
    int viewers = 10,
    String gameId = '1',
    String gameName = 'Just Chatting',
  }) => <String, dynamic>{
    'user_login': login,
    'user_name': login.toUpperCase(),
    'title': 'Stream of $login',
    'viewer_count': viewers,
    'game_id': gameId,
    'game_name': gameName,
    'thumbnail_url': 'https://t/{width}x{height}.jpg',
  };

  void stubToken({Map<String, dynamic>? body}) {
    when(
      () => dio.post<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => reply(
        body ?? <String, dynamic>{'access_token': 'tok', 'expires_in': 3600},
      ),
    );
  }

  void stubStreams(List<Map<String, dynamic>> rows) {
    when(
      () => dio.get<dynamic>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((_) async => reply(<String, dynamic>{'data': rows}));
  }

  TwitchApi api({DateTime Function()? now}) =>
      TwitchApi(clientId: 'id', clientSecret: 'secret', dio: dio, now: now);

  group('TwitchStream.fromJson', () {
    test('fills the thumbnail size and builds the channel url', () {
      final TwitchStream s = TwitchStream.fromJson(row('gaules', viewers: 5));
      expect(s.thumbnail, 'https://t/440x248.jpg');
      expect(s.url, 'https://twitch.tv/gaules');
      expect(s.viewers, 5);
      expect(s.name, 'GAULES');
    });

    test('tolerates missing fields', () {
      final TwitchStream s = TwitchStream.fromJson(<String, dynamic>{});
      expect(s.login, isEmpty);
      expect(s.viewers, 0);
      expect(s.thumbnail, isNull);
    });
  });

  group('genresOf', () {
    test('sums viewers per category, busiest first', () {
      final List<TwitchGenre> genres = genresOf(<TwitchStream>[
        TwitchStream.fromJson(row('a', viewers: 100, gameId: '1')),
        TwitchStream.fromJson(
          row('b', viewers: 300, gameId: '2', gameName: 'GTA V'),
        ),
        TwitchStream.fromJson(row('c', viewers: 250, gameId: '1')),
      ]);
      expect(genres.map((TwitchGenre g) => g.name), <String>[
        'Just Chatting',
        'GTA V',
      ]);
      expect(genres.first.viewers, 350);
    });

    test('skips streams without a category and honours the limit', () {
      final List<TwitchGenre> genres = genresOf(<TwitchStream>[
        TwitchStream.fromJson(<String, dynamic>{
          'user_login': 'x',
          'viewer_count': 9,
        }),
        TwitchStream.fromJson(row('a', gameId: '1', gameName: 'One')),
        TwitchStream.fromJson(row('b', gameId: '2', gameName: 'Two')),
      ], limit: 1);
      expect(genres, hasLength(1));
    });
  });

  group('russianStreams', () {
    test('asks Helix for Russian streams with the keys and a token', () async {
      stubToken();
      stubStreams(<Map<String, dynamic>>[row('a'), row('b')]);

      final List<TwitchStream> streams = await api().russianStreams(
        gameId: '33214',
      );

      expect(streams.map((TwitchStream s) => s.login), <String>['a', 'b']);
      final VerificationResult call = verify(
        () => dio.get<dynamic>(
          captureAny(),
          queryParameters: captureAny(named: 'queryParameters'),
          options: captureAny(named: 'options'),
        ),
      );
      expect(call.captured[0], 'https://api.twitch.tv/helix/streams');
      final Map<String, dynamic> query =
          call.captured[1] as Map<String, dynamic>;
      expect(query['language'], 'ru');
      expect(query['game_id'], '33214');
      final Options options = call.captured[2] as Options;
      expect(options.headers?['Client-Id'], 'id');
      expect(options.headers?['Authorization'], 'Bearer tok');
    });

    test('omits game_id for all categories', () async {
      stubToken();
      stubStreams(<Map<String, dynamic>>[]);

      await api().russianStreams();

      final Map<String, dynamic> query =
          verify(
                () => dio.get<dynamic>(
                  any(),
                  queryParameters: captureAny(named: 'queryParameters'),
                  options: any(named: 'options'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(query.containsKey('game_id'), isFalse);
    });

    test('one token serves several calls until it expires', () async {
      stubToken();
      stubStreams(<Map<String, dynamic>>[]);
      DateTime clock = DateTime(2026, 10, 2, 12);
      final TwitchApi sut = api(now: () => clock);

      await sut.russianStreams();
      await sut.russianStreams();
      verify(
        () => dio.post<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).called(1);

      clock = clock.add(const Duration(hours: 2));
      await sut.russianStreams();
      verify(
        () => dio.post<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).called(1);
    });

    test('throws without keys', () {
      final TwitchApi sut = TwitchApi(clientId: '', clientSecret: '', dio: dio);
      expect(sut.russianStreams, throwsA(isA<TwitchApiException>()));
    });

    test('a rejected secret becomes a readable error', () async {
      when(
        () => dio.post<dynamic>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(),
          response: Response<dynamic>(
            statusCode: 403,
            requestOptions: RequestOptions(),
          ),
        ),
      );

      await expectLater(
        api().russianStreams(),
        throwsA(
          isA<TwitchApiException>().having(
            (TwitchApiException e) => e.message,
            'message',
            contains('Client ID or Secret'),
          ),
        ),
      );
    });

    test('drops rows without a login', () async {
      stubToken();
      stubStreams(<Map<String, dynamic>>[
        row('ok'),
        <String, dynamic>{'title': 'ghost'},
      ]);
      expect(await api().russianStreams(), hasLength(1));
    });
  });
}
