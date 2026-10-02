import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

enum LiveService { youtube, twitch, kick }

class LiveTool {
  const LiveTool(this.exe, this.wingetId);

  final String exe;
  final String wingetId;

  String get name => p.basenameWithoutExtension(exe);
}

const LiveTool kYtDlp = LiveTool('yt-dlp.exe', 'yt-dlp.yt-dlp');
const LiveTool kStreamlink = LiveTool(
  'streamlink.exe',
  'Streamlink.Streamlink',
);

const Duration _kResolveTimeout = Duration(seconds: 60);

LiveTool toolFor(LiveService service) =>
    service == LiveService.youtube ? kYtDlp : kStreamlink;

/// A pasted link stays as it is; a bare channel name becomes the service URL,
/// and YouTube free text becomes a one-result search.
String normalizeLiveInput(LiveService service, String input) {
  final String text = input.trim();
  if (text.contains('://')) return text;
  return switch (service) {
    LiveService.twitch => 'https://twitch.tv/$text',
    LiveService.kick => 'https://kick.com/$text',
    LiveService.youtube => 'ytsearch1:$text',
  };
}

/// Looks for [tool] on PATH and in the places winget and the installers use.
String? findTool(
  LiveTool tool,
  Map<String, String> environment, {
  bool Function(String path) exists = _fileExists,
}) {
  final List<String> dirs = <String>[
    ...(environment['PATH'] ?? environment['Path'] ?? '')
        .split(';')
        .where((String d) => d.isNotEmpty),
    if (environment['LOCALAPPDATA'] case final String dir when dir.isNotEmpty)
      p.join(dir, 'Microsoft', 'WinGet', 'Links'),
    if (environment['ProgramFiles'] case final String dir when dir.isNotEmpty)
      p.join(dir, 'Streamlink', 'bin'),
    if (environment['ProgramFiles(x86)'] case final String dir
        when dir.isNotEmpty)
      p.join(dir, 'Streamlink', 'bin'),
  ];
  for (final String dir in dirs) {
    final String candidate = p.join(dir, tool.exe);
    if (exists(candidate)) return candidate;
  }
  return null;
}

bool _fileExists(String path) => File(path).existsSync();

class StreamResolveException implements Exception {
  const StreamResolveException(this.message, {this.missingTool});

  final String message;

  /// Set when the helper program is not installed.
  final LiveTool? missingTool;

  @override
  String toString() => 'StreamResolveException: $message';
}

final Provider<StreamResolver> streamResolverProvider =
    Provider<StreamResolver>((Ref ref) => const StreamResolver());

/// Turns a YouTube, Twitch or Kick link into a direct stream URL that any
/// player can open, using yt-dlp or streamlink.
class StreamResolver {
  const StreamResolver();

  static final Logger _log = Logger('StreamResolver');

  Future<String> resolve(LiveService service, String input) async {
    final LiveTool tool = toolFor(service);
    final String? exe = findTool(tool, Platform.environment);
    if (exe == null) {
      throw StreamResolveException(
        '${tool.name} is not installed',
        missingTool: tool,
      );
    }
    final String url = normalizeLiveInput(service, input);
    final List<String> args = service == LiveService.youtube
        ? <String>['-g', '-f', 'b/best', '--no-playlist', url]
        : <String>['--stream-url', url, 'best'];
    _log.info('resolving ${tool.name} $url');
    final ProcessResult result = await Process.run(
      exe,
      args,
    ).timeout(_kResolveTimeout);
    final String out = '${result.stdout}'.trim();
    final String line = out.split('\n').first.trim();
    if (result.exitCode != 0 || !line.startsWith('http')) {
      final String err = '${result.stderr}'.trim();
      _log.warning('resolve failed (${result.exitCode}): $err');
      throw StreamResolveException(
        err.isEmpty ? 'no stream found' : err.split('\n').last,
      );
    }
    return line;
  }
}
