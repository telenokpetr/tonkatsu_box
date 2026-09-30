import 'package:core/models/collection_item.dart';
import 'package:core/models/media_type.dart';

/// A record, so Riverpod `family` providers key on its value.
typedef WatchQuery = ({
  String title,
  String? originalTitle,
  int? year,
  bool isSerial,
});

/// The search JacRed gets for [item]; null for types with nothing to watch.
WatchQuery? watchQueryFor(CollectionItem item) {
  switch (item.mediaType) {
    case MediaType.movie:
      return _movieQuery(item);
    case MediaType.tvShow:
      return _tvQuery(item);
    case MediaType.animation:
      return item.platformId == AnimationSource.tvShow
          ? _tvQuery(item)
          : _movieQuery(item);
    case MediaType.anime:
      final String? title = item.anime?.title;
      if (title == null || title.isEmpty) return null;
      return (
        title: title,
        originalTitle: item.anime?.titleEnglish,
        year: item.releaseYear,
        isSerial: (item.anime?.episodes ?? 2) > 1,
      );
    case MediaType.game:
    case MediaType.visualNovel:
    case MediaType.manga:
    case MediaType.book:
    case MediaType.audio:
    case MediaType.custom:
      return null;
  }
}

WatchQuery? _movieQuery(CollectionItem item) {
  final String? title = item.movie?.title;
  if (title == null || title.isEmpty) return null;
  return (
    title: title,
    originalTitle: item.movie?.originalTitle,
    year: item.releaseYear,
    isSerial: false,
  );
}

WatchQuery? _tvQuery(CollectionItem item) {
  final String? title = item.tvShow?.title;
  if (title == null || title.isEmpty) return null;
  return (
    title: title,
    originalTitle: item.tvShow?.originalTitle,
    year: item.releaseYear,
    isSerial: true,
  );
}
