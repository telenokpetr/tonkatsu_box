import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../../shared/constants/platform_features.dart';
import '../settings/providers/watch_settings_provider.dart';

const String kVlcAndroidPackage = 'org.videolan.vlc';

// A torrent stalls for a moment now and then; VLC's 1 s default cache then
// drops out instead of riding through.
const int _vlcNetworkCachingMs = 5000;

final Provider<ExternalPlayerLauncher> externalPlayerProvider =
    Provider<ExternalPlayerLauncher>(
      (Ref ref) => const ExternalPlayerLauncher(),
    );

/// Install-folder suffixes under Program Files, per player and in the order
/// they are tried.
const Map<WatchPlayer, List<List<String>>> kWindowsPlayerPaths =
    <WatchPlayer, List<List<String>>>{
      WatchPlayer.mpcBe: <List<String>>[
        <String>['MPC-BE x64', 'mpc-be64.exe'],
        <String>['MPC-BE', 'mpc-be64.exe'],
        <String>['MPC-BE', 'mpc-be.exe'],
      ],
      WatchPlayer.mpcHc: <List<String>>[
        <String>['MPC-HC', 'mpc-hc64.exe'],
        <String>['MPC-HC', 'mpc-hc.exe'],
        <String>['K-Lite Codec Pack', 'MPC-HC64', 'mpc-hc64.exe'],
      ],
      WatchPlayer.vlc: <List<String>>[
        <String>['VideoLAN', 'VLC', 'vlc.exe'],
      ],
    };

/// Players tried, in order, for a given choice; empty for the built-in one.
List<WatchPlayer> playersToTry(WatchPlayer choice) => switch (choice) {
  WatchPlayer.auto => <WatchPlayer>[
    WatchPlayer.mpcBe,
    WatchPlayer.mpcHc,
    WatchPlayer.vlc,
  ],
  WatchPlayer.mpcBe ||
  WatchPlayer.mpcHc ||
  WatchPlayer.vlc => <WatchPlayer>[choice],
  WatchPlayer.builtIn => const <WatchPlayer>[],
};

/// First existing executable of [player] in the usual install folders.
String? findWindowsPlayer(
  WatchPlayer player,
  Map<String, String> environment, {
  bool Function(String path) exists = _fileExists,
}) {
  final List<List<String>>? suffixes = kWindowsPlayerPaths[player];
  if (suffixes == null) return null;
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
    for (final List<String> suffix in suffixes) {
      final String candidate = p.joinAll(<String>[root, ...suffix]);
      if (exists(candidate)) return candidate;
    }
  }
  return null;
}

/// `#EXTM3U` playlist that starts at [start] and wraps around, so "play this
/// episode and carry on" works in every player.
String buildPlaylist(List<String> urls, List<String> titles, int start) {
  final StringBuffer out = StringBuffer('#EXTM3U\n');
  for (int i = 0; i < urls.length; i++) {
    final int index = (start + i) % urls.length;
    out
      ..writeln('#EXTINF:-1,${titles[index].replaceAll('\n', ' ')}')
      ..writeln(urls[index]);
  }
  return out.toString();
}

bool _fileExists(String path) => File(path).existsSync();

/// Hands the stream (or a small playlist of a season pack) to the user's own
/// player, which brings its own audio and subtitle controls.
class ExternalPlayerLauncher {
  const ExternalPlayerLauncher();

  static final Logger _log = Logger('ExternalPlayerLauncher');

  /// False when no suitable player was found or it refused; the caller falls
  /// back to the built-in player. [start] is the episode to begin with.
  Future<bool> launch({
    required WatchPlayer choice,
    required List<String> urls,
    required List<String> titles,
    int start = 0,
  }) async {
    try {
      if (kIsWindowsApp) {
        return await _launchWindows(choice, urls, titles, start);
      }
      if (kIsAndroidApp && choice != WatchPlayer.builtIn) {
        return await _launchAndroid(urls[start], titles[start]);
      }
    } on Exception catch (e) {
      _log.warning('External player launch failed: $e');
    }
    return false;
  }

  Future<bool> _launchWindows(
    WatchPlayer choice,
    List<String> urls,
    List<String> titles,
    int start,
  ) async {
    for (final WatchPlayer player in playersToTry(choice)) {
      final String? exe = findWindowsPlayer(player, Platform.environment);
      if (exe == null) continue;
      final String target = urls.length == 1
          ? urls.first
          : await _writePlaylist(urls, titles, start);
      await Process.start(
        exe,
        _arguments(player, target),
        mode: ProcessStartMode.detached,
      );
      return true;
    }
    return false;
  }

  List<String> _arguments(WatchPlayer player, String target) =>
      switch (player) {
        WatchPlayer.vlc => <String>[
          target,
          '--network-caching=$_vlcNetworkCachingMs',
        ],
        WatchPlayer.mpcBe ||
        WatchPlayer.mpcHc => <String>[target, '/play', '/fullscreen'],
        WatchPlayer.auto || WatchPlayer.builtIn => <String>[target],
      };

  Future<String> _writePlaylist(
    List<String> urls,
    List<String> titles,
    int start,
  ) async {
    final File file = File(
      p.join(Directory.systemTemp.path, 'tonkatsu_watch.m3u8'),
    );
    await file.writeAsString(buildPlaylist(urls, titles, start));
    return file.path;
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
