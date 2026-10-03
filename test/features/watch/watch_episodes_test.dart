import 'package:flutter_test/flutter_test.dart';
import 'package:tonkatsu_box/core/api/torrserver_api.dart';
import 'package:tonkatsu_box/features/watch/watch_episodes.dart';

TorrServerFile file(String path, {int id = 1}) =>
    TorrServerFile(id: id, path: path, length: 1000);

void main() {
  group('parseEpisode', () {
    void expectId(String path, int? season, int? episode) {
      final EpisodeId id = parseEpisode(path);
      expect(id.season, season, reason: 'season of $path');
      expect(id.episode, episode, reason: 'episode of $path');
    }

    test('S01E05 forms', () {
      expectId('Show.S01E05.1080p.WEB-DL.mkv', 1, 5);
      expectId('Show s2e10 720p.mkv', 2, 10);
      expectId('Show.S03.E07.mkv', 3, 7);
    });

    test('1x05 form', () {
      expectId('Show 2x13 HDTV.avi', 2, 13);
    });

    test('Russian word forms with the season from the folder', () {
      expectId('Сезон 2/Серия 5.mkv', 2, 5);
      expectId('Show/Season 1/Episode 12.mkv', 1, 12);
    });

    test('anime style bare numbers', () {
      expectId('[Group] Show - 07 [1080p].mkv', null, 7);
      expectId('Show_12_v2.mkv', null, 12);
    });

    test('resolution, year and codec are not episodes', () {
      expectId('Movie.2019.1080p.x264.mkv', null, null);
      expectId('Movie 720p.mkv', null, null);
    });

    test('season only from a folder', () {
      expectId('Season 3/trailer.mkv', 3, null);
    });
  });

  group('episodeCode', () {
    test('pads season and episode', () {
      expect(episodeCode(const EpisodeId(season: 1, episode: 5)), 'S01E05');
      expect(episodeCode(const EpisodeId(episode: 7)), 'E07');
      expect(episodeCode(const EpisodeId(season: 1)), isNull);
    });
  });

  group('orderEpisodes', () {
    test('orders by season then episode, not by text', () {
      final List<EpisodeEntry> ordered = orderEpisodes(<TorrServerFile>[
        file('Show.S02E01.mkv', id: 4),
        file('Show.S01E10.mkv', id: 3),
        file('Show.S01E02.mkv', id: 2),
        file('Show.S01E01.mkv', id: 1),
      ]);
      expect(ordered.map((EpisodeEntry e) => e.file.id).toList(), <int>[
        1,
        2,
        3,
        4,
      ]);
    });

    test('files without numbers fall back to natural order', () {
      final List<EpisodeEntry> ordered = orderEpisodes(<TorrServerFile>[
        file('Extras/b10.mkv', id: 2),
        file('Extras/b2.mkv', id: 1),
      ]);
      expect(ordered.first.file.id, 1);
    });

    test('empty stays empty', () {
      expect(orderEpisodes(<TorrServerFile>[]), isEmpty);
    });
  });

  group('releaseSeasons', () {
    test('single season markers', () {
      expect(releaseSeasons('Breaking.Bad.S02.BDRip.1080p-SOFCJ'), <int>{2});
      expect(releaseSeasons('Во все тяжкие / 2 сезон [1080p]'), <int>{2});
      expect(releaseSeasons('Show (Сезон 4) WEB-DL'), <int>{4});
      expect(releaseSeasons('Show Season 7 Complete'), <int>{7});
    });

    test('ranges expand to every season', () {
      expect(releaseSeasons('Show Сезоны 1-3 720p'), <int>{1, 2, 3});
      expect(releaseSeasons('Show 1-5 сезон'), <int>{1, 2, 3, 4, 5});
      expect(releaseSeasons('Show S01-S03 1080p'), <int>{1, 2, 3});
    });

    test('quality, codec and year are not seasons', () {
      expect(releaseSeasons('Movie 2019 1080p x264 WEB-DL'), isNull);
      expect(releaseSeasons('Complete collection BDRip'), isNull);
    });

    test('an absurd or reversed range is ignored', () {
      expect(releaseSeasons('Show 9-2 сезон'), isNull);
      expect(releaseSeasons('Show Сезоны 1-99'), isNull);
    });
  });
}
