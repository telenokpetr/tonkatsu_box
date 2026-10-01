import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'api_dio.dart';
import 'service_url.dart';

class TorrServerApiException implements Exception {
  const TorrServerApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'TorrServerApiException($statusCode): $message';
}

class TorrServerFile {
  const TorrServerFile({
    required this.id,
    required this.path,
    required this.length,
  });

  factory TorrServerFile.fromJson(Map<String, dynamic> json) {
    return TorrServerFile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      path: json['path'] as String? ?? '',
      length: (json['length'] as num?)?.toInt() ?? 0,
    );
  }

  /// 1-based index TorrServer uses in `/stream?index=`.
  final int id;

  /// Path inside the torrent, `/`-separated.
  final String path;
  final int length;

  String get name => p.posix.basename(path);

  String get extension => p.posix.extension(path).toLowerCase();

  bool get isVideo => kVideoExtensions.contains(extension);
}

const Set<String> kVideoExtensions = <String>{
  '.mkv',
  '.mp4',
  '.avi',
  '.mov',
  '.m4v',
  '.ts',
  '.m2ts',
  '.webm',
  '.wmv',
  '.flv',
  '.mpg',
  '.mpeg',
};

class TorrServerTorrent {
  const TorrServerTorrent({
    required this.hash,
    required this.title,
    required this.files,
  });

  factory TorrServerTorrent.fromJson(Map<String, dynamic> json) {
    final Object? stats = json['file_stats'];
    return TorrServerTorrent(
      hash: json['hash'] as String? ?? '',
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      files: stats is List<dynamic>
          ? stats
                .whereType<Map<String, dynamic>>()
                .map(TorrServerFile.fromJson)
                .toList()
          : const <TorrServerFile>[],
    );
  }

  final String hash;
  final String title;

  /// Empty until TorrServer has fetched the torrent metadata from peers.
  final List<TorrServerFile> files;

  List<TorrServerFile> get videoFiles =>
      files.where((TorrServerFile f) => f.isVideo).toList();
}

/// Talks to a TorrServer (MatriX) instance: add a magnet, wait for its file
/// list, build the URL the player streams from.
class TorrServerApi {
  TorrServerApi({
    required String baseUrl,
    Dio? dio,
    this.pollInterval = const Duration(seconds: 1),
  }) : baseUrl = normalizeServiceUrl(baseUrl),
       _dio =
           dio ??
           createApiDio(
             connectTimeout: _connectTimeout,
             receiveTimeout: _receiveTimeout,
           );

  static final Logger _log = Logger('TorrServerApi');
  static const Duration _connectTimeout = Duration(seconds: 5);
  static const Duration _receiveTimeout = Duration(seconds: 30);

  final String baseUrl;
  final Dio _dio;
  final Duration pollInterval;

  bool get isConfigured => baseUrl.isNotEmpty;

  /// `/echo` answers with the server version as plain text.
  Future<String> echo() async {
    _requireConfigured();
    try {
      final Response<String> response = await _dio.get<String>(
        '$baseUrl/echo',
        options: Options(responseType: ResponseType.plain),
      );
      return (response.data ?? '').trim();
    } on DioException catch (e) {
      throw _wrap(e, '/echo');
    }
  }

  /// `save_to_db: false` keeps the torrent out of the user's saved list;
  /// TorrServer drops it by itself once nothing reads from it.
  Future<TorrServerTorrent> addTorrent(String magnet, {String? title}) {
    return _torrents(<String, dynamic>{
      'action': 'add',
      'link': magnet,
      'title': title ?? '',
      'save_to_db': false,
    });
  }

  /// A private tracker's .torrent carries its announce URL, which a bare
  /// magnet would lose, so the file goes up as is.
  Future<TorrServerTorrent> addTorrentFile(
    List<int> bytes, {
    required String fileName,
  }) {
    return _post(
      '/torrent/upload',
      FormData.fromMap(<String, dynamic>{
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
        'save': 'false',
      }),
    );
  }

  Future<TorrServerTorrent> getTorrent(String hash) {
    return _torrents(<String, dynamic>{'action': 'get', 'hash': hash});
  }

  /// Polls until the metadata arrives. A dead magnet never does, so the
  /// [timeout] is what turns that into an error instead of a spinner.
  Future<TorrServerTorrent> waitForFiles(
    String hash, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final Stopwatch clock = Stopwatch()..start();
    while (true) {
      final TorrServerTorrent torrent = await getTorrent(hash);
      if (torrent.files.isNotEmpty) return torrent;
      if (clock.elapsed >= timeout) {
        _log.warning('no metadata for $hash after ${clock.elapsed.inSeconds}s');
        throw const TorrServerApiException(
          'No metadata from peers — the torrent may be dead',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  String streamUrl(TorrServerTorrent torrent, TorrServerFile file) {
    final String name = Uri.encodeComponent(file.name);
    return '$baseUrl/stream/$name?link=${torrent.hash}&index=${file.id}&play';
  }

  Future<TorrServerTorrent> _torrents(Map<String, dynamic> body) {
    return _post('/torrents', body);
  }

  Future<TorrServerTorrent> _post(String path, Object body) async {
    _requireConfigured();
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '$baseUrl$path',
        data: body,
      );
      final Object? data = response.data;
      if (data is Map<String, dynamic>) {
        final TorrServerTorrent torrent = TorrServerTorrent.fromJson(data);
        _log.info(
          'POST $path -> hash=${torrent.hash} files=${torrent.files.length}',
        );
        return torrent;
      }
      throw const TorrServerApiException('Unexpected TorrServer response');
    } on DioException catch (e) {
      throw _wrap(e, path);
    }
  }

  void _requireConfigured() {
    if (!isConfigured) {
      throw const TorrServerApiException('TorrServer URL is not set');
    }
  }

  TorrServerApiException _wrap(DioException e, String path) {
    _log.warning('$path failed: ${e.message}');
    return TorrServerApiException(
      e.message ?? 'TorrServer request failed',
      statusCode: e.response?.statusCode,
    );
  }
}
