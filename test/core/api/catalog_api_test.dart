import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tonkatsu_box/core/api/catalog_api.dart';

import '../../helpers/test_helpers.dart';

void main() {
  late MockDio mockDio;

  setUpAll(registerAllFallbacks);

  setUp(() => mockDio = MockDio());

  Response<dynamic> json(Object? data) => Response<dynamic>(
    data: data,
    statusCode: 200,
    requestOptions: RequestOptions(),
  );

  group('CatalogEntry.fromJson', () {
    test('reads IMDb and Kinopoisk fields', () {
      final CatalogEntry e = CatalogEntry.fromJson(<String, dynamic>{
        'imdb': 'tt0111161',
        'kp': 326,
        'title': 'Побег',
        'original': 'The Shawshank Redemption',
        'year': 1994,
        'rating': 9.3,
      });
      expect(e.imdb, 'tt0111161');
      expect(e.kinopoisk, 326);
      expect(e.title, 'Побег');
      expect(e.original, 'The Shawshank Redemption');
      expect(e.year, 1994);
      expect(e.rating, 9.3);
    });

    test('an empty or missing imdb id becomes null', () {
      expect(CatalogEntry.fromJson(<String, dynamic>{'imdb': ''}).imdb, isNull);
      expect(CatalogEntry.fromJson(<String, dynamic>{}).imdb, isNull);
    });
  });

  group('CatalogData.fromJson', () {
    test('parses lists, drops untitled rows, reads the date', () {
      final CatalogData data = CatalogData.fromJson(<String, dynamic>{
        'updated': '2026-10-01T20:43:59+00:00',
        'lists': <String, dynamic>{
          'movies_top': <dynamic>[
            <String, dynamic>{'title': 'A'},
            <String, dynamic>{'title': ''},
            'junk',
          ],
          'bad': 5,
        },
      });
      expect(data.lists.keys, <String>['movies_top']);
      expect(data.lists['movies_top'], hasLength(1));
      expect(data.updated, DateTime.utc(2026, 10, 1, 20, 43, 59));
    });

    test('a body without lists is empty, not an error', () {
      final CatalogData data = CatalogData.fromJson(<String, dynamic>{});
      expect(data.lists, isEmpty);
      expect(data.updated, isNull);
    });
  });

  group('CatalogApi.fetch', () {
    test('requests the normalized URL', () async {
      when(() => mockDio.get<dynamic>(any())).thenAnswer(
        (_) async => json(<String, dynamic>{'lists': <String, dynamic>{}}),
      );
      final CatalogApi api = CatalogApi(
        url: '127.0.0.1:8099/catalog.json',
        dio: mockDio,
      );

      await api.fetch();

      verify(
        () => mockDio.get<dynamic>('http://127.0.0.1:8099/catalog.json'),
      ).called(1);
    });

    test('throws without an address and on a non-object body', () async {
      expect(
        () => CatalogApi(url: '', dio: mockDio).fetch(),
        throwsA(isA<CatalogApiException>()),
      );
      when(
        () => mockDio.get<dynamic>(any()),
      ).thenAnswer((_) async => json('x'));
      expect(
        () => CatalogApi(url: 'h', dio: mockDio).fetch(),
        throwsA(isA<CatalogApiException>()),
      );
    });

    test('wraps network errors', () async {
      when(() => mockDio.get<dynamic>(any())).thenThrow(
        DioException(requestOptions: RequestOptions(), message: 'refused'),
      );
      await expectLater(
        CatalogApi(url: 'h', dio: mockDio).fetch(),
        throwsA(
          isA<CatalogApiException>().having(
            (CatalogApiException e) => e.message,
            'message',
            'refused',
          ),
        ),
      );
    });
  });
}
