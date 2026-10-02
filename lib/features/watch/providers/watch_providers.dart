import 'package:core/models/movie.dart';
import 'package:core/models/tv_show.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/catalog_api.dart';
import '../../../core/api/iptv_api.dart';
import '../../../core/api/jacred_api.dart';
import '../../../core/api/tmdb_api.dart';
import '../../../core/api/torrserver_api.dart';
import '../../settings/providers/watch_settings_provider.dart';
import '../watch_query.dart';

/// Rebuilt whenever the address or key changes in Settings.
final Provider<JacRedApi> jacRedApiProvider = Provider<JacRedApi>((Ref ref) {
  final WatchSettingsState settings = ref.watch(watchSettingsProvider);
  return JacRedApi(baseUrl: settings.jacRedUrl, apiKey: settings.jacRedApiKey);
});

final Provider<TorrServerApi> torrServerApiProvider = Provider<TorrServerApi>((
  Ref ref,
) {
  final WatchSettingsState settings = ref.watch(watchSettingsProvider);
  return TorrServerApi(baseUrl: settings.torrServerUrl);
});

final AutoDisposeFutureProviderFamily<List<JacRedTorrent>, WatchQuery>
watchResultsProvider = FutureProvider.autoDispose
    .family<List<JacRedTorrent>, WatchQuery>((Ref ref, WatchQuery query) {
      return ref
          .watch(jacRedApiProvider)
          .search(
            title: query.title,
            originalTitle: query.originalTitle,
            year: query.year,
            isSerial: query.isSerial,
          );
    });

final Provider<CatalogApi> catalogApiProvider = Provider<CatalogApi>((Ref ref) {
  return CatalogApi(url: ref.watch(watchSettingsProvider).catalogUrl);
});

final AutoDisposeFutureProvider<CatalogData> catalogProvider =
    FutureProvider.autoDispose<CatalogData>(
      (Ref ref) => ref.watch(catalogApiProvider).fetch(),
    );

/// What TMDB knows about a catalog entry: the poster and the title in the
/// user's language. Null when the entry has no IMDb id or TMDB has no match.
class CatalogCard {
  const CatalogCard({this.title, this.posterUrl});

  final String? title;
  final String? posterUrl;
}

/// Kept alive on purpose: scrolling back must not refetch 250 posters.
final FutureProviderFamily<CatalogCard?, CatalogEntry> catalogCardProvider =
    FutureProvider.family<CatalogCard?, CatalogEntry>((
      Ref ref,
      CatalogEntry entry,
    ) async {
      final String? imdb = entry.imdb;
      if (imdb == null) return null;
      try {
        final TmdbFindResult found = await ref
            .read(tmdbApiProvider)
            .findByImdbId(imdb);
        final Movie? movie = found.firstMovie;
        if (movie != null) {
          return CatalogCard(
            title: movie.title,
            posterUrl: movie.posterThumbUrl,
          );
        }
        final TvShow? show = found.firstTvShow;
        if (show != null) {
          return CatalogCard(title: show.title, posterUrl: show.posterThumbUrl);
        }
      } on Exception {
        return null;
      }
      return null;
    });

/// The channel list is the same all session; a reopen must not refetch it.
final FutureProvider<List<IptvChannel>> iptvChannelsProvider =
    FutureProvider<List<IptvChannel>>((Ref ref) {
      final String url = ref.watch(watchSettingsProvider).iptvUrl;
      return IptvApi(url: url.isEmpty ? kDefaultIptvUrl : url).fetch();
    });
