import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tonkatsu_box/features/watch/stream_resolver.dart';
import 'package:tonkatsu_box/features/watch/youtube_feed.dart';

void main() {
  const Map<String, String> env = <String, String>{
    'APPDATA': r'C:\Users\Me\AppData\Roaming',
  };

  group('youtubeCookiesPath', () {
    test('lives in the app data folder', () {
      expect(
        youtubeCookiesPath(env),
        p.join(
          r'C:\Users\Me\AppData\Roaming',
          'Tonkatsu Box',
          'Tonkatsu Box',
          'youtube_cookies.txt',
        ),
      );
    });
  });

  group('youtubeCookieArgs', () {
    test('prefers the saved cookie file over the browser', () {
      final List<String> args = youtubeCookieArgs(
        'vivaldi',
        env,
        exists: (String f) => true,
      );
      expect(args.first, '--cookies');
      expect(args.last, youtubeCookiesPath(env));
      expect(args, isNot(contains('--cookies-from-browser')));
    });

    test('falls back to the browser store without a saved file', () {
      expect(
        youtubeCookieArgs('vivaldi', env, exists: (String f) => false),
        <String>['--cookies-from-browser', 'vivaldi'],
      );
    });

    test('no browser and no file means no cookie arguments', () {
      expect(youtubeCookieArgs('', env, exists: (String f) => false), isEmpty);
    });
  });

  group('isBrowserLocked', () {
    test('recognizes the yt-dlp message for a cookie store in use', () {
      expect(
        isBrowserLocked(
          'ERROR: Could not copy Chrome cookie database. See https://x',
        ),
        isTrue,
      );
      expect(isBrowserLocked('the cookie database is locked'), isTrue);
    });

    test('other failures are not a locked browser', () {
      expect(isBrowserLocked('Sign in to confirm you are not a bot'), isFalse);
      expect(isBrowserLocked(''), isFalse);
    });
  });
}
