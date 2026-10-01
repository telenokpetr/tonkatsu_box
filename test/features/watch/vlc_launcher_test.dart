import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tonkatsu_box/features/watch/vlc_launcher.dart';

void main() {
  group('findWindowsVlc', () {
    final String x64 = p.join(
      r'C:\Program Files',
      'VideoLAN',
      'VLC',
      'vlc.exe',
    );
    final String x86 = p.join(
      r'C:\Program Files (x86)',
      'VideoLAN',
      'VLC',
      'vlc.exe',
    );
    final String perUser = p.join(
      r'C:\Users\Me\AppData\Local',
      'Programs',
      'VideoLAN',
      'VLC',
      'vlc.exe',
    );
    const Map<String, String> env = <String, String>{
      'ProgramFiles': r'C:\Program Files',
      'ProgramFiles(x86)': r'C:\Program Files (x86)',
      'LOCALAPPDATA': r'C:\Users\Me\AppData\Local',
    };

    test('finds the 32-bit install the way it sits on this PC', () {
      expect(findWindowsVlc(env, exists: (String path) => path == x86), x86);
    });

    test('prefers the 64-bit install when both exist', () {
      expect(
        findWindowsVlc(
          env,
          exists: (String path) => path == x64 || path == x86,
        ),
        x64,
      );
    });

    test('finds a per-user install', () {
      expect(
        findWindowsVlc(env, exists: (String path) => path == perUser),
        perUser,
      );
    });

    test('returns null when VLC is nowhere', () {
      expect(findWindowsVlc(env, exists: (String path) => false), isNull);
    });

    test('ignores missing or empty environment variables', () {
      expect(
        findWindowsVlc(const <String, String>{
          'ProgramFiles': '',
        }, exists: (String path) => true),
        isNull,
      );
      expect(
        findWindowsVlc(const <String, String>{}, exists: (String path) => true),
        isNull,
      );
    });
  });
}
