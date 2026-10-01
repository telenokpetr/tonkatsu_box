import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

import 'api_dio.dart';
import 'service_url.dart';

class CatalogApiException implements Exception {
  const CatalogApiException(this.message);

  final String message;

  @override
  String toString() => 'CatalogApiException: $message';
}

class CatalogEntry {
  const CatalogEntry({
    required this.title,
    required this.original,
    this.imdb,
    this.kinopoisk,
    this.year,
    this.rating,
  });

  factory CatalogEntry.fromJson(Map<String, dynamic> json) {
    final Object? imdb = json['imdb'];
    return CatalogEntry(
      title: json['title'] as String? ?? '',
      original: json['original'] as String? ?? '',
      imdb: imdb is String && imdb.isNotEmpty ? imdb : null,
      kinopoisk: (json['kp'] as num?)?.toInt(),
      year: (json['year'] as num?)?.toInt(),
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }

  final String title;
  final String original;
  final String? imdb;
  final int? kinopoisk;
  final int? year;
  final double? rating;
}

class CatalogData {
  const CatalogData({required this.updated, required this.lists});

  factory CatalogData.fromJson(Map<String, dynamic> json) {
    final Object? rawLists = json['lists'];
    final Map<String, List<CatalogEntry>> lists = <String, List<CatalogEntry>>{
      if (rawLists is Map<String, dynamic>)
        for (final MapEntry<String, dynamic> e in rawLists.entries)
          if (e.value is List<dynamic>)
            e.key: (e.value as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .map(CatalogEntry.fromJson)
                .where((CatalogEntry c) => c.title.isNotEmpty)
                .toList(),
    };
    final Object? updated = json['updated'];
    return CatalogData(
      updated: updated is String ? DateTime.tryParse(updated) : null,
      lists: lists,
    );
  }

  final DateTime? updated;
  final Map<String, List<CatalogEntry>> lists;
}

/// Reads the `catalog.json` that the catalog container builds every couple of
/// days (IMDb datasets plus Kinopoisk lists).
class CatalogApi {
  CatalogApi({required String url, Dio? dio})
    : url = normalizeServiceUrl(url),
      _dio =
          dio ??
          createApiDio(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 30),
          );

  static final Logger _log = Logger('CatalogApi');

  final String url;
  final Dio _dio;

  bool get isConfigured => url.isNotEmpty;

  Future<CatalogData> fetch() async {
    if (!isConfigured) {
      throw const CatalogApiException('Catalog address is not set');
    }
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(url);
      final Object? data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const CatalogApiException('Unexpected catalog response');
      }
      final CatalogData catalog = CatalogData.fromJson(data);
      final String sizes = catalog.lists.entries
          .map(
            (MapEntry<String, List<CatalogEntry>> e) =>
                '${e.key}=${e.value.length}',
          )
          .join(', ');
      _log.info('catalog loaded: $sizes');
      return catalog;
    } on DioException catch (e) {
      _log.warning('catalog request failed: ${e.message}');
      throw CatalogApiException(e.message ?? 'Catalog request failed');
    }
  }
}
