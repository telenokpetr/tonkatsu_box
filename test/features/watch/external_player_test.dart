import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tonkatsu_box/features/settings/providers/watch_settings_provider.dart';
import 'package:tonkatsu_box/features/watch/external_player.dart';

void main() {
  const Map<String, String> env = <String, String>{
    'ProgramFiles': r'C:\Program Files',
    'ProgramFiles(x86)': r'C:\Program Files (x86)',
    'LOCALAPPDATA': r'C:\Users\Me\AppData\Local',
  };

  String path(String root, List<String> parts) =>
      p.joinAll(<String>[root, ...parts]);

  group('findWindowsPlayer', () {
    test('finds the K-Lite MPC-HC the way it sits on this PC', () {
      final String klite = path(r'C:\Program Files (x86)', <String>[
        'K-Lite Codec Pack',
        'MPC-HC64',
        'mpc-hc64.exe',
      ]);
      expect(
        findWindowsPlayer(
          WatchPlayer.mpcHc,
          env,
          exists: (String f) => f == klite,
        ),
        klite,
      );
    });

    test('finds MPC-BE x64 and the 32-bit VLC', () {
      final String be = path(r'C:\Program Files', <String>[
        'MPC-BE x64',
        'mpc-be64.exe',
      ]);
      final String vlc = path(r'C:\Program Files (x86)', <String>[
        'VideoLAN',
        'VLC',
        'vlc.exe',
      ]);
      expect(
        findWindowsPlayer(
          WatchPlayer.mpcBe,
          env,
          exists: (String f) => f == be,
        ),
        be,
      );
      expect(
        findWindowsPlayer(WatchPlayer.vlc, env, exists: (String f) => f == vlc),
        vlc,
      );
    });

    test('finds a per-user install', () {
      final String vlc = path(r'C:\Users\Me\AppData\Local', <String>[
        'Programs',
        'VideoLAN',
        'VLC',
        'vlc.exe',
      ]);
      expect(
        findWindowsPlayer(WatchPlayer.vlc, env, exists: (String f) => f == vlc),
        vlc,
      );
    });

    test('null when missing, for the built-in player, or without env', () {
      expect(
        findWindowsPlayer(WatchPlayer.vlc, env, exists: (String f) => false),
        isNull,
      );
      expect(
        findWindowsPlayer(WatchPlayer.builtIn, env, exists: (String f) => true),
        isNull,
      );
      expect(
        findWindowsPlayer(WatchPlayer.vlc, const <String, String>{
          'ProgramFiles': '',
        }, exists: (String f) => true),
        isNull,
      );
    });
  });

  group('playersToTry', () {
    test('auto prefers MPC-BE, then MPC-HC, then VLC', () {
      expect(playersToTry(WatchPlayer.auto), <WatchPlayer>[
        WatchPlayer.mpcBe,
        WatchPlayer.mpcHc,
        WatchPlayer.vlc,
      ]);
    });

    test('a named player is tried alone, the built-in one never', () {
      expect(playersToTry(WatchPlayer.vlc), <WatchPlayer>[WatchPlayer.vlc]);
      expect(playersToTry(WatchPlayer.builtIn), isEmpty);
    });
  });

  group('buildPlaylist', () {
    test('starts at the chosen episode and wraps around', () {
      final String m3u = buildPlaylist(
        <String>['u1', 'u2', 'u3'],
        <String>['e1', 'e2', 'e3'],
        1,
      );
      expect(
        m3u,
        '#EXTM3U\n#EXTINF:-1,e2\nu2\n#EXTINF:-1,e3\nu3\n#EXTINF:-1,e1\nu1\n',
      );
    });

    test('a title with a line break stays on one line', () {
      expect(
        buildPlaylist(<String>['u'], <String>['a\nb'], 0),
        contains('#EXTINF:-1,a b\n'),
      );
    });
  });
}
