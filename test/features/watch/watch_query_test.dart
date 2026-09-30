import 'package:core/models/media_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonkatsu_box/features/watch/watch_query.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('watchQueryFor', () {
    test('movie carries title, original title and year', () {
      final WatchQuery? query = watchQueryFor(
        createTestCollectionItem(
          mediaType: MediaType.movie,
          movie: createTestMovie(
            title: 'Matrix RU',
            originalTitle: 'The Matrix',
            releaseYear: 1999,
          ),
        ),
      );

      expect(query, isNotNull);
      expect(query!.title, 'Matrix RU');
      expect(query.originalTitle, 'The Matrix');
      expect(query.year, 1999);
      expect(query.isSerial, isFalse);
    });

    test('tv show is a serial', () {
      final WatchQuery? query = watchQueryFor(
        createTestCollectionItem(
          mediaType: MediaType.tvShow,
          tvShow: createTestTvShow(title: 'Show', originalTitle: 'Show EN'),
        ),
      );

      expect(query?.title, 'Show');
      expect(query?.originalTitle, 'Show EN');
      expect(query?.isSerial, isTrue);
    });

    test('animation follows its TV or movie source', () {
      final WatchQuery? tv = watchQueryFor(
        createTestCollectionItem(
          mediaType: MediaType.animation,
          platformId: AnimationSource.tvShow,
          tvShow: createTestTvShow(title: 'Cartoon Series'),
        ),
      );
      final WatchQuery? film = watchQueryFor(
        createTestCollectionItem(
          mediaType: MediaType.animation,
          platformId: AnimationSource.movie,
          movie: createTestMovie(title: 'Cartoon Film'),
        ),
      );

      expect(tv?.title, 'Cartoon Series');
      expect(tv?.isSerial, isTrue);
      expect(film?.title, 'Cartoon Film');
      expect(film?.isSerial, isFalse);
    });

    test('anime searches by its title', () {
      final WatchQuery? query = watchQueryFor(
        createTestCollectionItem(
          mediaType: MediaType.anime,
          anime: createTestAnime(title: 'Shingeki no Kyojin'),
        ),
      );

      expect(query?.title, 'Shingeki no Kyojin');
    });

    test('an item whose media is not loaded has no query', () {
      expect(
        watchQueryFor(createTestCollectionItem(mediaType: MediaType.movie)),
        isNull,
      );
    });

    test('types with nothing to watch have no query', () {
      for (final MediaType type in <MediaType>[
        MediaType.game,
        MediaType.manga,
        MediaType.book,
        MediaType.audio,
        MediaType.visualNovel,
        MediaType.custom,
      ]) {
        expect(
          watchQueryFor(createTestCollectionItem(mediaType: type)),
          isNull,
          reason: type.name,
        );
      }
    });
  });
}
