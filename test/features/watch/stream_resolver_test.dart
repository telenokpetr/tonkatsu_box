import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tonkatsu_box/core/api/iptv_api.dart';
import 'package:tonkatsu_box/features/watch/stream_resolver.dart';

void main() {
  group('normalizeLiveInput', () {
    test('keeps a pasted link as it is', () {
      expect(
        normalizeLiveInput(LiveService.twitch, ' https://twitch.tv/abc '),
        'https://twitch.tv/abc',
      );
    });

    test('turns a bare channel name into the service URL', () {
      expect(
        normalizeLiveInput(LiveService.twitch, 'shroud'),
        'https://twitch.tv/shroud',
      );
      expect(
        normalizeLiveInput(LiveService.kick, 'xqc'),
        'https://kick.com/xqc',
      );
    });

    test('free YouTube text becomes a one-result search', () {
      expect(
        normalizeLiveInput(LiveService.youtube, 'lofi radio'),
        'ytsearch1:lofi radio',
      );
    });
  });

  group('toolFor', () {
    test('YouTube uses yt-dlp, Twitch and Kick use streamlink', () {
      expect(toolFor(LiveService.youtube), kYtDlp);
      expect(toolFor(LiveService.twitch), kStreamlink);
      expect(toolFor(LiveService.kick), kStreamlink);
    });
  });

  group('findTool', () {
    final String link = p.join(
      r'C:\Users\Me\AppData\Local',
      'Microsoft',
      'WinGet',
      'Links',
      'yt-dlp.exe',
    );
    final String installed = p.join(
      r'C:\Program Files',
      'Streamlink',
      'bin',
      'streamlink.exe',
    );
    const Map<String, String> env = <String, String>{
      'PATH': r'C:\Windows;C:\Tools',
      'LOCALAPPDATA': r'C:\Users\Me\AppData\Local',
      'ProgramFiles': r'C:\Program Files',
    };

    test('finds a winget link and a Program Files install', () {
      expect(findTool(kYtDlp, env, exists: (String f) => f == link), link);
      expect(
        findTool(kStreamlink, env, exists: (String f) => f == installed),
        installed,
      );
    });

    test('finds a tool on PATH first', () {
      final String onPath = p.join(r'C:\Tools', 'yt-dlp.exe');
      expect(
        findTool(kYtDlp, env, exists: (String f) => f == onPath || f == link),
        onPath,
      );
    });

    test('finds a winget package folder and a per-user Streamlink', () {
      final String pkg = p.join(
        r'C:\Users\Me\AppData\Local',
        'Microsoft',
        'WinGet',
        'Packages',
        'yt-dlp.yt-dlp_Microsoft.Winget.Source_8wekyb3d8bbwe',
      );
      final String exe = p.join(pkg, 'yt-dlp.exe');
      expect(
        findTool(
          kYtDlp,
          env,
          exists: (String f) => f == exe,
          listDirs: (String d) => <String>[
            pkg,
            p.join(d, 'Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe'),
          ],
        ),
        exe,
      );
      final String perUser = p.join(
        r'C:\Users\Me\AppData\Local',
        'Programs',
        'Streamlink',
        'bin',
        'streamlink.exe',
      );
      expect(
        findTool(kStreamlink, env, exists: (String f) => f == perUser),
        perUser,
      );
    });

    test('ignores package folders of other programs', () {
      final String other = p.join(
        r'C:\Users\Me\AppData\Local',
        'Microsoft',
        'WinGet',
        'Packages',
        'Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe',
        'yt-dlp.exe',
      );
      expect(
        findTool(
          kYtDlp,
          env,
          exists: (String f) => f == other,
          listDirs: (String d) => <String>[p.dirname(other)],
        ),
        isNull,
      );
    });

    test('null when the tool is nowhere', () {
      expect(findTool(kYtDlp, env, exists: (String f) => false), isNull);
    });
  });

  group('parseM3u', () {
    const String playlist = '''#EXTM3U
#EXTINF:-1 tvg-id="a" tvg-logo="http://x/logo.png" group-title="News",First, News (1080p)
http://example.com/a.m3u8
#EXTINF:-1 group-title="",No Logo
http://example.com/b.m3u8
#EXTINF:-1,Orphan without url
#EXTINF:-1,Third
#EXTVLCOPT:http-user-agent=x
http://example.com/c.m3u8
''';

    test('reads name, logo, group and url', () {
      final List<IptvChannel> channels = parseM3u(playlist);
      expect(channels.first.name, 'First, News (1080p)');
      expect(channels.first.logo, 'http://x/logo.png');
      expect(channels.first.group, 'News');
      expect(channels.first.url, 'http://example.com/a.m3u8');
    });

    test(
      'empty attributes become null and entries without a url are skipped',
      () {
        final List<IptvChannel> channels = parseM3u(playlist);
        expect(channels[1].logo, isNull);
        expect(channels[1].group, isNull);
        expect(channels.map((IptvChannel c) => c.name), <String>[
          'First, News (1080p)',
          'No Logo',
          'Third',
        ]);
      },
    );

    test('an empty body gives no channels', () {
      expect(parseM3u(''), isEmpty);
    });
  });
}
