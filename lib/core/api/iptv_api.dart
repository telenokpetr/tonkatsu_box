import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import 'api_dio.dart';

/// Public Russian channels from the iptv-org collection.
const String kDefaultIptvUrl =
    'https://iptv-org.github.io/iptv/countries/ru.m3u';

class IptvChannel {
  const IptvChannel({
    required this.name,
    required this.url,
    this.logo,
    this.group,
  });

  final String name;
  final String url;
  final String? logo;
  final String? group;
}

final RegExp _kAttribute = RegExp(r'([\w-]+)="([^"]*)"');

/// The comma that starts the channel name; commas inside the quoted
/// attributes (and later inside the name itself) do not count.
int _titleComma(String line) {
  bool quoted = false;
  for (int i = 0; i < line.length; i++) {
    final String c = line[i];
    if (c == '"') quoted = !quoted;
    if (c == ',' && !quoted) return i;
  }
  return -1;
}

/// Parses an `#EXTM3U` playlist: an `#EXTINF` line followed by the stream URL.
List<IptvChannel> parseM3u(String text) {
  final List<IptvChannel> channels = <IptvChannel>[];
  String? pending;
  for (final String raw in text.split('\n')) {
    final String line = raw.trim();
    if (line.startsWith('#EXTINF')) {
      pending = line;
    } else if (pending != null && line.isNotEmpty && !line.startsWith('#')) {
      final Map<String, String> attributes = <String, String>{
        for (final RegExpMatch m in _kAttribute.allMatches(pending))
          m.group(1) ?? '': m.group(2) ?? '',
      };
      final int comma = _titleComma(pending);
      final String name = comma >= 0 ? pending.substring(comma + 1).trim() : '';
      if (name.isNotEmpty) {
        final String logo = attributes['tvg-logo'] ?? '';
        final String group = attributes['group-title'] ?? '';
        channels.add(
          IptvChannel(
            name: name,
            url: line,
            logo: logo.isEmpty ? null : logo,
            group: group.isEmpty ? null : group,
          ),
        );
      }
      pending = null;
    }
  }
  return channels;
}

class IptvApi {
  IptvApi({String url = kDefaultIptvUrl, Dio? dio})
    : _url = url,
      _dio =
          dio ??
          createApiDio(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            responseType: ResponseType.plain,
          );

  static final Logger _log = Logger('IptvApi');

  final String _url;
  final Dio _dio;

  Future<List<IptvChannel>> fetch() async {
    try {
      final Response<String> response = await _dio.get<String>(_url);
      final List<IptvChannel> channels = parseM3u(response.data ?? '');
      _log.info('iptv playlist: ${channels.length} channels');
      return channels;
    } on DioException catch (e) {
      _log.warning('iptv request failed: ${e.message}');
      rethrow;
    }
  }
}
