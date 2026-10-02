import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import 'api_dio.dart';

const String _kTokenUrl = 'https://id.twitch.tv/oauth2/token';
const String _kHelix = 'https://api.twitch.tv/helix';
const int _kThumbWidth = 440;
const int _kThumbHeight = 248;
const Duration _kTokenMargin = Duration(seconds: 60);

class TwitchApiException implements Exception {
  const TwitchApiException(this.message);

  final String message;

  @override
  String toString() => 'TwitchApiException: $message';
}

class TwitchStream {
  const TwitchStream({
    required this.login,
    required this.name,
    required this.title,
    required this.viewers,
    this.gameId,
    this.gameName,
    this.thumbnail,
  });

  factory TwitchStream.fromJson(Map<String, dynamic> json) {
    final String? raw = json['thumbnail_url'] as String?;
    return TwitchStream(
      login: json['user_login'] as String? ?? '',
      name: json['user_name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      viewers: (json['viewer_count'] as num?)?.toInt() ?? 0,
      gameId: json['game_id'] as String?,
      gameName: json['game_name'] as String?,
      thumbnail: raw
          ?.replaceAll('{width}', '$_kThumbWidth')
          .replaceAll('{height}', '$_kThumbHeight'),
    );
  }

  final String login;
  final String name;
  final String title;
  final int viewers;
  final String? gameId;
  final String? gameName;
  final String? thumbnail;

  String get url => 'https://twitch.tv/$login';
}

class TwitchGenre {
  const TwitchGenre({
    required this.id,
    required this.name,
    required this.viewers,
  });

  final String id;
  final String name;
  final int viewers;
}

/// The categories the given streams are playing, busiest first; streams with
/// no category are skipped.
List<TwitchGenre> genresOf(List<TwitchStream> streams, {int limit = 14}) {
  final Map<String, ({String name, int viewers})> byId =
      <String, ({String name, int viewers})>{};
  for (final TwitchStream s in streams) {
    final String? id = s.gameId;
    final String? name = s.gameName;
    if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
    final ({String name, int viewers})? known = byId[id];
    byId[id] = (name: name, viewers: (known?.viewers ?? 0) + s.viewers);
  }
  final List<TwitchGenre> genres = <TwitchGenre>[
    for (final MapEntry<String, ({String name, int viewers})> e in byId.entries)
      TwitchGenre(id: e.key, name: e.value.name, viewers: e.value.viewers),
  ]..sort((TwitchGenre a, TwitchGenre b) => b.viewers.compareTo(a.viewers));
  return genres.take(limit).toList();
}

/// Live Russian-language streams through the official Helix API, with the
/// user's own application keys (client credentials).
class TwitchApi {
  TwitchApi({
    required String clientId,
    required String clientSecret,
    Dio? dio,
    DateTime Function()? now,
  }) : _clientId = clientId.trim(),
       _clientSecret = clientSecret.trim(),
       _now = now ?? DateTime.now,
       _dio =
           dio ??
           createApiDio(
             connectTimeout: const Duration(seconds: 8),
             receiveTimeout: const Duration(seconds: 20),
           );

  static final Logger _log = Logger('TwitchApi');

  final String _clientId;
  final String _clientSecret;
  final DateTime Function() _now;
  final Dio _dio;

  String? _token;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isConfigured => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  Future<String> _accessToken({bool force = false}) async {
    if (!force && _token != null && _now().isBefore(_expires)) {
      return _token ?? '';
    }
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        _kTokenUrl,
        data: <String, String>{
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'grant_type': 'client_credentials',
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final Object? data = response.data;
      if (data is! Map<String, dynamic> || data['access_token'] is! String) {
        throw const TwitchApiException('Twitch gave no access token');
      }
      final int seconds = (data['expires_in'] as num?)?.toInt() ?? 3600;
      _token = data['access_token'] as String;
      _expires = _now().add(Duration(seconds: seconds)).subtract(_kTokenMargin);
      return _token ?? '';
    } on DioException catch (e) {
      _log.warning('token request failed: ${e.message}');
      throw TwitchApiException(
        e.response?.statusCode == 400 || e.response?.statusCode == 403
            ? 'Twitch rejected the Client ID or Secret'
            : e.message ?? 'Twitch token request failed',
      );
    }
  }

  /// Streams in Russian, busiest first; [gameId] narrows to one category.
  Future<List<TwitchStream>> russianStreams({
    String? gameId,
    int first = 100,
  }) async {
    if (!isConfigured) {
      throw const TwitchApiException('Twitch keys are not set');
    }
    final Map<String, dynamic> query = <String, dynamic>{
      'language': 'ru',
      'first': first,
      if (gameId != null && gameId.isNotEmpty) 'game_id': gameId,
    };
    Future<Response<dynamic>> call(String token) => _dio.get<dynamic>(
      '$_kHelix/streams',
      queryParameters: query,
      options: Options(
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Client-Id': _clientId,
        },
      ),
    );
    try {
      Response<dynamic> response;
      try {
        response = await call(await _accessToken());
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) rethrow;
        response = await call(await _accessToken(force: true));
      }
      final Object? data = response.data;
      final Object? rows = data is Map<String, dynamic> ? data['data'] : null;
      final List<TwitchStream> streams = rows is List<dynamic>
          ? rows
                .whereType<Map<String, dynamic>>()
                .map(TwitchStream.fromJson)
                .where((TwitchStream s) => s.login.isNotEmpty)
                .toList()
          : <TwitchStream>[];
      _log.info('twitch streams game=$gameId: ${streams.length}');
      return streams;
    } on DioException catch (e) {
      _log.warning('streams request failed: ${e.message}');
      throw TwitchApiException(e.message ?? 'Twitch request failed');
    }
  }
}
