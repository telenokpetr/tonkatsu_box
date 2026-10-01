import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../shared/constants/platform_features.dart';

const String kVlcAndroidPackage = 'org.videolan.vlc';

// A torrent stalls for a moment now and then; VLC's 1 s default cache then
// drops out instead of riding through.
const int _vlcNetworkCachingMs = 5000;

final Provider<VlcLauncher> vlcLauncherProvider = Provider<VlcLauncher>(
  (Ref ref) => const VlcLauncher(),
);

/// First `vlc.exe` found in the usual install folders, or null.
String? findWindowsVlc(
  Map<String, String> environment, {
  bool Function(String path) exists = _fileExists,
}) {
  final List<String> roots = <String>[
    for (final String key in <String>[
      'ProgramFiles',
      'ProgramW6432',
      'ProgramFiles(x86)',
    ])
      if (environment[key] case final String dir when dir.isNotEmpty) dir,
    if (environment['LOCALAPPDATA'] case final String dir when dir.isNotEmpty)
      p.join(dir, 'Programs'),
  ];
  for (final String root in roots) {
    final String candidate = p.join(root, 'VideoLAN', 'VLC', 'vlc.exe');
    if (exists(candidate)) return candidate;
  }
  return null;
}

bool _fileExists(String path) => File(path).existsSync();

/// Hands a stream URL to the user's own VLC, which brings its own audio and
/// subtitle controls.
class VlcLauncher {
  const VlcLauncher();

  static final Logger _log = Logger('VlcLauncher');

  /// False when VLC is missing or refused; the caller falls back to the
  /// built-in player.
  Future<bool> launch({required String url, required String title}) async {
    try {
      if (kIsWindowsApp) return await _launchWindows(url);
      if (kIsAndroidApp) return await _launchAndroid(url, title);
    } on Exception catch (e) {
      _log.warning('VLC launch failed: $e');
    }
    return false;
  }

  Future<bool> _launchWindows(String url) async {
    final String? vlc = findWindowsVlc(Platform.environment);
    if (vlc == null) return false;
    await Process.start(vlc, <String>[
      url,
      '--network-caching=$_vlcNetworkCachingMs',
    ], mode: ProcessStartMode.detached);
    return true;
  }

  Future<bool> _launchAndroid(String url, String title) async {
    await AndroidIntent(
      action: 'action_view',
      data: url,
      type: 'video/*',
      package: kVlcAndroidPackage,
      arguments: <String, dynamic>{'title': title},
    ).launch();
    return true;
  }
}
