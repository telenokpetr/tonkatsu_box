import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import 'api_dio.dart';
import 'service_url.dart';

class JacRedApiException implements Exception {
  const JacRedApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'JacRedApiException($statusCode): $message';
}

class JacRedTorrent {
  const JacRedTorrent({
    required this.title,
    required this.magnet,
    required this.sizeBytes,
    required this.seeders,
    required this.peers,
    this.tracker,
    this.quality,
    this.languages = const <String>[],
    this.publishedAt,
  });

  factory JacRedTorrent.fromJson(Map<String, dynamic> json) {
    final Object? info = json['info'];
    final Object? quality = info is Map<String, dynamic>
        ? info['quality']
        : null;
    final Object? languages = json['languages'];
    final Object? published = json['PublishDate'];
    return JacRedTorrent(
      title: json['Title'] as String? ?? '',
      magnet: json['MagnetUri'] as String? ?? '',
      sizeBytes: (json['Size'] as num?)?.toInt() ?? 0,
      seeders: (json['Seeders'] as num?)?.toInt() ?? 0,
      peers: (json['Peers'] as num?)?.toInt() ?? 0,
      tracker: json['Tracker'] as String?,
      quality: quality is num && quality > 0 ? quality.toInt() : null,
      languages: languages is List<dynamic>
          ? languages.whereType<String>().toList()
          : const <String>[],
      publishedAt: published is String ? DateTime.tryParse(published) : null,
    );
  }

  final String title;
  final String magnet;
  final int sizeBytes;
  final int seeders;
  final int peers;
  final String? tracker;

  /// Vertical resolution (720, 1080, 2160) as detected by JacRed.
  final int? quality;

  /// ISO 639-2 codes of the audio tracks JacRed found with ffprobe.
  final List<String> languages;
  final DateTime? publishedAt;
}

/// Searches a self-hosted JacRed through its Jackett-compatible endpoint.
class JacRedApi {
  JacRedApi({required String baseUrl, String apiKey = '', Dio? dio})
    : baseUrl = normalizeServiceUrl(baseUrl),
      _apiKey = apiKey.trim(),
      _dio =
          dio ??
          createApiDio(
            connectTimeout: _connectTimeout,
            receiveTimeout: _receiveTimeout,
          );

  static final Logger _log = Logger('JacRedApi');
  static const Duration _connectTimeout = Duration(seconds: 5);
  static const Duration _receiveTimeout = Duration(seconds: 30);
  static const String _resultsPath = '/api/v2.0/indexers/all/results';

  final String baseUrl;
  final String _apiKey;
  final Dio _dio;

  bool get isConfigured => baseUrl.isNotEmpty;

  /// Card search, the same shape Lampa sends: JacRed matches on the original
  /// title and year far better than on a free-text query.
  Future<List<JacRedTorrent>> search({
    required String title,
    String? originalTitle,
    int? year,
    bool isSerial = false,
  }) async {
    if (!isConfigured) {
      throw const JacRedApiException('JacRed URL is not set');
    }
    final Map<String, dynamic> query = <String, dynamic>{
      'title': title,
      'Query': title,
      if (originalTitle != null && originalTitle.isNotEmpty)
        'title_original': originalTitle,
      if (year != null && year > 0) 'year': year,
      'is_serial': isSerial ? 2 : 1,
      if (_apiKey.isNotEmpty) 'apikey': _apiKey,
    };
    final Map<String, dynamic> body = await _get(_resultsPath, query);
    final Object? results = body['Results'];
    if (results is! List<dynamic>) return const <JacRedTorrent>[];
    final List<JacRedTorrent> torrents = results
        .whereType<Map<String, dynamic>>()
        .map(JacRedTorrent.fromJson)
        .where((JacRedTorrent t) => t.magnet.isNotEmpty)
        .toList();
    torrents.sort(
      (JacRedTorrent a, JacRedTorrent b) => b.seeders.compareTo(a.seeders),
    );
    return torrents;
  }

  /// `/api/v1.0/conf` answers without touching the index, so it tells "server
  /// is up" apart from "search is slow".
  Future<bool> ping() async {
    if (!isConfigured) return false;
    final Map<String, dynamic> body = await _get(
      '/api/v1.0/conf',
      <String, dynamic>{if (_apiKey.isNotEmpty) 'apikey': _apiKey},
    );
    return body['jacred'] == true;
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, dynamic> query,
  ) async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '$baseUrl$path',
        queryParameters: query,
      );
      final Object? data = response.data;
      if (data is Map<String, dynamic>) return data;
      throw const JacRedApiException('Unexpected JacRed response');
    } on DioException catch (e) {
      _log.warning('GET $path failed: ${e.message}');
      final int? status = e.response?.statusCode;
      throw JacRedApiException(
        status == 401 || status == 403
            ? 'JacRed rejected the API key'
            : e.message ?? 'JacRed request failed',
        statusCode: status,
      );
    }
  }
}
