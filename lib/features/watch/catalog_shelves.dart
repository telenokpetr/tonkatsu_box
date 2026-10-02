import 'package:core/models/movie.dart';
import 'package:core/models/tv_show.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/catalog_api.dart';
import '../../core/api/iptv_api.dart';
import '../../core/api/tmdb_api.dart';
import '../recommendations/providers/recommendations_provider.dart';
import 'providers/watch_providers.dart';

/// The Animation genre id on TMDB, the same for movies and TV.
const int _kAnimationGenre = 16;
const int _kShelfPages = 2;

/// One title on a catalog shelf, whichever source it came from.
class CatalogItem {
  const CatalogItem({
    required this.title,
    required this.isSerial,
    this.original,
    this.year,
    this.rating,
    this.posterUrl,
    this.entry,
    this.streamUrl,
    this.group,
  });

  factory CatalogItem.fromMovie(Movie m) => CatalogItem(
    title: m.title,
    original: m.originalTitle,
    year: m.releaseYear,
    rating: m.rating,
    posterUrl: m.posterThumbUrl,
    isSerial: false,
  );

  factory CatalogItem.fromTv(TvShow t) => CatalogItem(
    title: t.title,
    original: t.originalTitle,
    year: t.firstAirYear,
    rating: t.rating,
    posterUrl: t.posterThumbUrl,
    isSerial: true,
  );

  /// A list entry from the catalog container; its poster is resolved lazily.
  factory CatalogItem.fromEntry(CatalogEntry e, {required bool isSerial}) =>
      CatalogItem(
        title: e.title,
        original: e.original,
        year: e.year,
        rating: e.rating,
        isSerial: isSerial,
        entry: e,
      );

  /// A TV channel: the tap plays this URL instead of searching torrents.
  factory CatalogItem.fromChannel(IptvChannel c) => CatalogItem(
    title: c.name,
    posterUrl: c.logo,
    isSerial: false,
    streamUrl: c.url,
    group: c.group,
  );

  final String title;
  final String? original;
  final int? year;
  final double? rating;
  final String? posterUrl;
  final bool isSerial;
  final CatalogEntry? entry;
  final String? streamUrl;
  final String? group;

  String get key => '$title|$year|$isSerial|${streamUrl ?? ''}';
}

/// Highest rating first, unrated last; ties keep their original order.
List<CatalogItem> mergeByRating(List<CatalogItem> a, List<CatalogItem> b) {
  final List<CatalogItem> all = <CatalogItem>[...a, ...b];
  final Map<CatalogItem, int> order = <CatalogItem, int>{
    for (int i = 0; i < all.length; i++) all[i]: i,
  };
  all.sort((CatalogItem x, CatalogItem y) {
    final double rx = x.rating ?? -1;
    final double ry = y.rating ?? -1;
    final int byRating = ry.compareTo(rx);
    return byRating != 0 ? byRating : (order[x] ?? 0).compareTo(order[y] ?? 0);
  });
  return dedupeItems(all);
}

List<CatalogItem> dedupeItems(List<CatalogItem> items) {
  final Set<String> seen = <String>{};
  return <CatalogItem>[
    for (final CatalogItem item in items)
      if (seen.add(item.key)) item,
  ];
}

/// Shelf ids in tab order. TMDB shelves are queried live; the container ones
/// read the lists it refreshes every couple of days.
const List<String> kShelfIds = <String>[
  'recs',
  'trend_movies',
  'trend_series',
  'top_series',
  'cartoons',
  'old_cartoons',
  'soviet_cartoons',
  'anime',
  'old_anime',
  'tv',
  'movies_top',
  'series_top',
  'movies_popular',
  'kp_movies_top',
  'kp_series_top',
  'kp_popular',
];

const Set<String> kSerialShelves = <String>{
  'trend_series',
  'top_series',
  'series_top',
  'kp_series_top',
};

Future<List<CatalogItem>> _movies(
  Future<List<Movie>> Function(int page) fetch,
) async {
  final List<CatalogItem> out = <CatalogItem>[];
  for (int page = 1; page <= _kShelfPages; page++) {
    out.addAll((await fetch(page)).map(CatalogItem.fromMovie));
  }
  return dedupeItems(out);
}

Future<List<CatalogItem>> _series(
  Future<List<TvShow>> Function(int page) fetch,
) async {
  final List<CatalogItem> out = <CatalogItem>[];
  for (int page = 1; page <= _kShelfPages; page++) {
    out.addAll((await fetch(page)).map(CatalogItem.fromTv));
  }
  return dedupeItems(out);
}

/// Movies and TV of one kind merged into a single rating-ordered shelf.
Future<List<CatalogItem>> _both(
  Future<List<Movie>> Function(int page) movies,
  Future<List<TvShow>> Function(int page) tv,
) async {
  final List<List<CatalogItem>> parts = await Future.wait(
    <Future<List<CatalogItem>>>[_movies(movies), _series(tv)],
  );
  return mergeByRating(parts[0], parts[1]);
}

final AutoDisposeFutureProviderFamily<List<CatalogItem>, String> shelfProvider =
    FutureProvider.autoDispose.family<List<CatalogItem>, String>((
      Ref ref,
      String id,
    ) async {
      final TmdbApi tmdb = ref.read(tmdbApiProvider);
      switch (id) {
        case 'recs':
          final RecommendationResult result = await ref.watch(
            recommendationsProvider.future,
          );
          return dedupeItems(<CatalogItem>[
            for (final RecommendationRowUi row in result.rows)
              for (final RecommendedItem item in row.items)
                if (item.media is Movie)
                  CatalogItem.fromMovie(item.media as Movie)
                else if (item.media is TvShow)
                  CatalogItem.fromTv(item.media as TvShow),
          ]);
        case 'tv':
          final List<IptvChannel> channels = await ref.watch(
            iptvChannelsProvider.future,
          );
          return <CatalogItem>[
            for (final IptvChannel c in channels) CatalogItem.fromChannel(c),
          ];
        case 'trend_movies':
          return _movies((int p) => tmdb.getTrendingMovies(page: p));
        case 'trend_series':
          return _series((int p) => tmdb.getTrendingTvShows(page: p));
        case 'top_series':
          return _series((int p) => tmdb.getTopRatedTvShows(page: p));
        case 'cartoons':
          return _both(
            (int p) => tmdb.discoverMovies(
              genreId: _kAnimationGenre,
              releaseDateGte: '1990-01-01',
              voteCountGte: 500,
              sortBy: 'vote_average.desc',
              page: p,
            ),
            (int p) => tmdb.discoverTvShows(
              genreId: _kAnimationGenre,
              firstAirDateGte: '1990-01-01',
              voteCountGte: 300,
              sortBy: 'vote_average.desc',
              page: p,
            ),
          );
        case 'old_cartoons':
          return _both(
            (int p) => tmdb.discoverMovies(
              genreId: _kAnimationGenre,
              releaseDateLte: '1989-12-31',
              voteCountGte: 300,
              sortBy: 'vote_average.desc',
              page: p,
            ),
            (int p) => tmdb.discoverTvShows(
              genreId: _kAnimationGenre,
              firstAirDateLte: '1989-12-31',
              voteCountGte: 100,
              sortBy: 'vote_average.desc',
              page: p,
            ),
          );
        case 'soviet_cartoons':
          return _both(
            (int p) => tmdb.discoverMovies(
              genreId: _kAnimationGenre,
              originalLanguage: 'ru',
              releaseDateLte: '1991-12-31',
              voteCountGte: 15,
              sortBy: 'vote_average.desc',
              page: p,
            ),
            (int p) => tmdb.discoverTvShows(
              genreId: _kAnimationGenre,
              originalLanguage: 'ru',
              firstAirDateLte: '1991-12-31',
              voteCountGte: 10,
              sortBy: 'vote_average.desc',
              page: p,
            ),
          );
        case 'anime':
          return _both(
            (int p) => tmdb.discoverMovies(
              genreId: _kAnimationGenre,
              originalLanguage: 'ja',
              voteCountGte: 300,
              page: p,
            ),
            (int p) => tmdb.discoverTvShows(
              genreId: _kAnimationGenre,
              originalLanguage: 'ja',
              voteCountGte: 200,
              page: p,
            ),
          );
        case 'old_anime':
          return _both(
            (int p) => tmdb.discoverMovies(
              genreId: _kAnimationGenre,
              originalLanguage: 'ja',
              releaseDateLte: '2005-12-31',
              voteCountGte: 200,
              sortBy: 'vote_average.desc',
              page: p,
            ),
            (int p) => tmdb.discoverTvShows(
              genreId: _kAnimationGenre,
              originalLanguage: 'ja',
              firstAirDateLte: '2005-12-31',
              voteCountGte: 150,
              sortBy: 'vote_average.desc',
              page: p,
            ),
          );
      }
      final CatalogData data = await ref.watch(catalogProvider.future);
      return <CatalogItem>[
        for (final CatalogEntry e in data.lists[id] ?? const <CatalogEntry>[])
          CatalogItem.fromEntry(e, isSerial: kSerialShelves.contains(id)),
      ];
    });

/// Alternates two relevance-ordered lists so neither kind buries the other.
List<CatalogItem> interleave(List<CatalogItem> a, List<CatalogItem> b) {
  final List<CatalogItem> out = <CatalogItem>[];
  for (int i = 0; i < a.length || i < b.length; i++) {
    if (i < a.length) out.add(a[i]);
    if (i < b.length) out.add(b[i]);
  }
  return dedupeItems(out);
}

/// Text search over TMDB movies and series for the catalog search field.
final AutoDisposeFutureProviderFamily<List<CatalogItem>, String>
catalogSearchProvider = FutureProvider.autoDispose
    .family<List<CatalogItem>, String>((Ref ref, String query) async {
      final TmdbApi tmdb = ref.read(tmdbApiProvider);
      final List<Movie> movies = await tmdb.searchMovies(query);
      final List<TvShow> series = await tmdb.searchTvShows(query);
      return interleave(
        movies.map(CatalogItem.fromMovie).toList(),
        series.map(CatalogItem.fromTv).toList(),
      );
    });
