import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/catalog_api.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_typography.dart';
import '../../../shared/widgets/screen_app_bar.dart';
import '../catalog_shelves.dart';
import '../providers/watch_providers.dart';
import '../watch_query.dart';
import 'watch_screen.dart';

const double _kCardWidth = 150;
const double _kGridGap = AppSpacing.md;

String _shelfLabel(S l, String id) => switch (id) {
  'recs' => l.catalogRecs,
  'trend_movies' => l.catalogMoviesTrending,
  'trend_series' => l.catalogSeriesTrending,
  'top_series' => l.catalogSeriesTop,
  'cartoons' => l.catalogCartoons,
  'old_cartoons' => l.catalogOldCartoons,
  'soviet_cartoons' => l.catalogSovietCartoons,
  'anime' => l.catalogAnime,
  'old_anime' => l.catalogOldAnime,
  'movies_top' => l.catalogImdbMovies,
  'series_top' => l.catalogImdbSeries,
  'movies_popular' => l.catalogImdbNew,
  'kp_movies_top' => l.catalogKpMovies,
  'kp_series_top' => l.catalogKpSeries,
  'kp_popular' => l.catalogKpPopular,
  _ => id,
};

/// Recommendations, TMDB shelves (series, cartoons, old cartoons, anime) and
/// the IMDb and Kinopoisk lists from the catalog container, with a search over
/// TMDB. A tap on a title goes straight to the torrent picker.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String text) => setState(() => _query = text.trim());

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final bool searching = _query.isNotEmpty;
    return DefaultTabController(
      length: kShelfIds.length,
      child: Scaffold(
        appBar: ScreenAppBar(title: l.catalogTitle),
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l.catalogSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searching
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            _setQuery('');
                          },
                        )
                      : null,
                ),
                onSubmitted: _setQuery,
              ),
            ),
            if (!searching)
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: <Widget>[
                  for (final String id in kShelfIds)
                    Tab(text: _shelfLabel(l, id)),
                ],
              ),
            Expanded(
              child: searching
                  ? _SearchResults(query: _query)
                  : TabBarView(
                      children: <Widget>[
                        for (final String id in kShelfIds) _ShelfView(id: id),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final S l = S.of(context);
    return ref
        .watch(catalogSearchProvider(query))
        .when(
          data: (List<CatalogItem> items) => items.isEmpty
              ? _Message(l.catalogEmpty)
              : _CatalogGrid(items: items, showRank: false),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stack) =>
              _Message(l.catalogLoadFailed('$error')),
        );
  }
}

class _ShelfView extends ConsumerWidget {
  const _ShelfView({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final S l = S.of(context);
    final AsyncValue<List<CatalogItem>> shelf = ref.watch(shelfProvider(id));
    return shelf.when(
      data: (List<CatalogItem> items) =>
          items.isEmpty ? _Message(_emptyText(l)) : _CatalogGrid(items: items),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) => _Message(
        l.catalogLoadFailed(
          error is CatalogApiException ? error.message : '$error',
        ),
      ),
    );
  }

  String _emptyText(S l) {
    if (id == 'recs') return l.catalogRecsEmpty;
    if (id.startsWith('kp_')) return l.catalogNoKinopoisk;
    return l.catalogEmpty;
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}

class _CatalogGrid extends StatelessWidget {
  const _CatalogGrid({required this.items, this.showRank = true});

  final List<CatalogItem> items;
  final bool showRank;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _kCardWidth,
        mainAxisSpacing: _kGridGap,
        crossAxisSpacing: _kGridGap,
        childAspectRatio: 0.52,
      ),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) => _CatalogCardView(
        key: ValueKey<String>(items[index].key),
        rank: showRank ? index + 1 : null,
        item: items[index],
      ),
    );
  }
}

class _CatalogCardView extends ConsumerWidget {
  const _CatalogCardView({required this.rank, required this.item, super.key});

  final int? rank;
  final CatalogItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogEntry? entry = item.entry;
    // Container entries carry no poster; TMDB shelves already have one.
    final CatalogCard? card = entry == null
        ? null
        : ref.watch(catalogCardProvider(entry)).valueOrNull;
    final String title = card?.title ?? item.title;
    final String? poster = item.posterUrl ?? card?.posterUrl;
    final double? rating = item.rating;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: () {
        final String original = item.original ?? '';
        final WatchQuery query = (
          title: title,
          originalTitle: original.isEmpty ? null : original,
          year: item.year,
          isSerial: item.isSerial,
        );
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => WatchScreen(query: query),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: poster == null
                      ? ColoredBox(color: AppColors.surface)
                      : CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          errorWidget: (BuildContext c, String u, Object e) =>
                              ColoredBox(color: AppColors.surface),
                        ),
                ),
                if (rank != null)
                  Positioned(
                    left: AppSpacing.xs,
                    top: AppSpacing.xs,
                    child: _Badge(text: '$rank'),
                  ),
                if (rating != null && rating > 0)
                  Positioned(
                    right: AppSpacing.xs,
                    top: AppSpacing.xs,
                    child: _Badge(text: rating.toStringAsFixed(1)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall,
          ),
          if (item.year != null)
            Text(
              '${item.year}',
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
