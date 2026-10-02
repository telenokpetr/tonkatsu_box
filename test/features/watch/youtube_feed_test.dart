import 'package:flutter_test/flutter_test.dart';
import 'package:tonkatsu_box/features/watch/watch_format.dart';
import 'package:tonkatsu_box/features/watch/youtube_feed.dart';

void main() {
  group('parseYoutubeFeed', () {
    test('reads id, title, channel, duration and the last thumbnail', () {
      final List<YoutubeVideo> videos = parseYoutubeFeed(<String, dynamic>{
        'entries': <dynamic>[
          <String, dynamic>{
            'id': 'abc123',
            'title': 'A video',
            'channel': 'Some Channel',
            'duration': 125.0,
            'thumbnails': <dynamic>[
              <String, dynamic>{'url': 'http://t/small.jpg'},
              <String, dynamic>{'url': 'http://t/large.jpg'},
            ],
          },
        ],
      });
      expect(videos, hasLength(1));
      expect(videos.single.id, 'abc123');
      expect(videos.single.title, 'A video');
      expect(videos.single.channel, 'Some Channel');
      expect(videos.single.durationSeconds, 125);
      expect(videos.single.thumbnail, 'http://t/large.jpg');
      expect(videos.single.url, 'https://www.youtube.com/watch?v=abc123');
    });

    test('falls back to uploader and a default thumbnail', () {
      final YoutubeVideo video = parseYoutubeFeed(<String, dynamic>{
        'entries': <dynamic>[
          <String, dynamic>{'id': 'x1', 'title': 'T', 'uploader': 'Up'},
        ],
      }).single;
      expect(video.channel, 'Up');
      expect(video.thumbnail, 'https://i.ytimg.com/vi/x1/mqdefault.jpg');
      expect(video.durationSeconds, isNull);
    });

    test('drops rows without an id or title and survives junk', () {
      final List<YoutubeVideo> videos = parseYoutubeFeed(<String, dynamic>{
        'entries': <dynamic>[
          <String, dynamic>{'title': 'no id'},
          <String, dynamic>{'id': 'nt', 'title': ''},
          'junk',
          null,
          <String, dynamic>{'id': 'ok', 'title': 'Fine'},
        ],
      });
      expect(videos.map((YoutubeVideo v) => v.id), <String>['ok']);
    });

    test('a dump without entries is empty', () {
      expect(parseYoutubeFeed(<String, dynamic>{}), isEmpty);
      expect(parseYoutubeFeed(<String, dynamic>{'entries': 5}), isEmpty);
    });
  });

  group('YoutubeFeed', () {
    test('uses the yt-dlp pseudo URLs for the personal feeds', () {
      expect(YoutubeFeed.subscriptions.selector, ':ytsubs');
      expect(YoutubeFeed.recommended.selector, ':ytrec');
      expect(YoutubeFeed.watchLater.selector, ':ytwatchlater');
      expect(YoutubeFeed.history.selector, ':ythistory');
    });
  });

  group('formatClock', () {
    test('minutes and seconds under an hour', () {
      expect(formatClock(const Duration(seconds: 65)), '1:05');
      expect(formatClock(const Duration(seconds: 9)), '0:09');
    });

    test('hours pad the minutes', () {
      expect(formatClock(const Duration(seconds: 3725)), '1:02:05');
    });
  });
}
