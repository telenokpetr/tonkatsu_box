import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../settings/providers/watch_settings_provider.dart';
import 'stream_resolver.dart';

const int _kFeedSize = 48;
const Duration _kFeedTimeout = Duration(seconds: 90);

/// The personal feeds yt-dlp can read with a browser's YouTube login.
enum YoutubeFeed {
  subscriptions(':ytsubs'),
  recommended(':ytrec'),
  watchLater(':ytwatchlater'),
  history(':ythistory');

  const YoutubeFeed(this.selector);

  final String selector;
}

class YoutubeVideo {
  const YoutubeVideo({
    required this.id,
    required this.title,
    this.channel,
    this.durationSeconds,
    this.thumbnail,
  });

  final String id;
  final String title;
  final String? channel;
  final int? durationSeconds;
  final String? thumbnail;

  String get url => 'https://www.youtube.com/watch?v=$id';
}

/// Entries of a `--flat-playlist -J` dump; rows without an id or title are
/// dropped (deleted and private videos come through that way).
List<YoutubeVideo> parseYoutubeFeed(Map<String, dynamic> json) {
  final Object? entries = json['entries'];
  if (entries is! List<dynamic>) return const <YoutubeVideo>[];
  final List<YoutubeVideo> videos = <YoutubeVideo>[];
  for (final Object? e in entries) {
    if (e is! Map<String, dynamic>) continue;
    final Object? id = e['id'];
    final Object? title = e['title'];
    if (id is! String || title is! String || title.isEmpty) continue;
    final Object? thumbs = e['thumbnails'];
    String? thumb = e['thumbnail'] as String?;
    if (thumb == null && thumbs is List<dynamic> && thumbs.isNotEmpty) {
      final Object? last = thumbs.last;
      if (last is Map<String, dynamic>) thumb = last['url'] as String?;
    }
    videos.add(
      YoutubeVideo(
        id: id,
        title: title,
        channel: (e['channel'] ?? e['uploader']) as String?,
        durationSeconds: (e['duration'] as num?)?.toInt(),
        thumbnail: thumb ?? 'https://i.ytimg.com/vi/$id/mqdefault.jpg',
      ),
    );
  }
  return videos;
}

class YoutubeFeedException implements Exception {
  const YoutubeFeedException(this.message, {this.missingTool});

  final String message;
  final LiveTool? missingTool;

  @override
  String toString() => 'YoutubeFeedException: $message';
}

/// Reads a feed of the user's own account through the browser's cookies;
/// no password ever passes through the app.
class YoutubeFeedApi {
  const YoutubeFeedApi();

  static final Logger _log = Logger('YoutubeFeedApi');

  Future<List<YoutubeVideo>> fetch(YoutubeFeed feed, String browser) async {
    final String? exe = findTool(kYtDlp, Platform.environment);
    if (exe == null) {
      throw const YoutubeFeedException(
        'yt-dlp is not installed',
        missingTool: kYtDlp,
      );
    }
    final String? deno = findTool(kDeno, Platform.environment);
    final ProcessResult result = await Process.run(
      exe,
      <String>[
        if (deno != null) ...<String>['--js-runtimes', 'deno:$deno'],
        '--cookies-from-browser',
        browser,
        '--flat-playlist',
        '--playlist-end',
        '$_kFeedSize',
        '-J',
        feed.selector,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(_kFeedTimeout);
    final String out = '${result.stdout}'.trim();
    if (result.exitCode != 0 || !out.startsWith('{')) {
      final String err = '${result.stderr}'.trim();
      _log.warning('feed ${feed.name} failed (${result.exitCode}): $err');
      throw YoutubeFeedException(
        err.isEmpty ? 'no data' : err.split('\n').last,
      );
    }
    final Object? json = jsonDecode(out);
    final List<YoutubeVideo> videos = json is Map<String, dynamic>
        ? parseYoutubeFeed(json)
        : const <YoutubeVideo>[];
    _log.info('feed ${feed.name}: ${videos.length} videos');
    return videos;
  }
}

final AutoDisposeFutureProviderFamily<List<YoutubeVideo>, YoutubeFeed>
youtubeFeedProvider = FutureProvider.autoDispose
    .family<List<YoutubeVideo>, YoutubeFeed>(
      (Ref ref, YoutubeFeed feed) => const YoutubeFeedApi().fetch(
        feed,
        ref.watch(watchSettingsProvider).youtubeBrowser,
      ),
    );
