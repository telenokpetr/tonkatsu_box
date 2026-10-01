import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/catalog_api.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_typography.dart';
import '../../../shared/widgets/screen_app_bar.dart';
import '../providers/watch_providers.dart';
import '../watch_query.dart';
import 'watch_screen.dart';

const double _kCardWidth = 150;
const double _kGridGap = AppSpacing.md;

/// A catalog list the container can produce, in tab order.
class _CatalogTab {
  const _CatalogTab(this.key, this.isSerial);

  final String key;
  final bool isSerial;
}

const List<_CatalogTab> _kTabs = <_CatalogTab>[
  _CatalogTab('movies_top', false),
  _CatalogTab('series_top', true),
  _CatalogTab('movies_popular', false),
  _CatalogTab('kp_movies_top', false),
  _CatalogTab('kp_series_top', true),
  _CatalogTab('kp_popular', false),
];

String _tabLabel(S l, String key) => switch (key) {
  'movies_top' => l.catalogImdbMovies,
  'series_top' => l.catalogImdbSeries,
  'movies_popular' => l.catalogImdbNew,
  'kp_movies_top' => l.catalogKpMovies,
  'kp_series_top' => l.catalogKpSeries,
  'kp_popular' => l.catalogKpPopular,
  _ => key,
};

/// IMDb and Kinopoisk top lists from the catalog container; a tap on a title
/// goes straight to the torrent picker.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final S l = S.of(context);
    final AsyncValue<CatalogData> catalog = ref.watch(catalogProvider);
    return Scaffold(
      appBar: ScreenAppBar(title: l.catalogTitle),
      body: catalog.when(
        data: (CatalogData data) => _CatalogTabs(data: data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              l.catalogLoadFailed(
                error is CatalogApiException ? error.message : '$error',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogTabs extends StatelessWidget {
  const _CatalogTabs({required this.data});

  final CatalogData data;

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final List<_CatalogTab> tabs = <_CatalogTab>[
      for (final _CatalogTab tab in _kTabs)
        if ((data.lists[tab.key] ?? const <CatalogEntry>[]).isNotEmpty) tab,
    ];
    final bool hasKinopoisk = tabs.any(
      (_CatalogTab t) => t.key.startsWith('kp_'),
    );
    final DateTime? updated = data.updated?.toLocal();
    if (tabs.isEmpty) {
      return Center(child: Text(l.catalogLoadFailed('empty catalog')));
    }
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: <Widget>[
          TabBar(
            isScrollable: true,
            tabs: <Widget>[
              for (final _CatalogTab tab in tabs)
                Tab(text: _tabLabel(l, tab.key)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                for (final _CatalogTab tab in tabs)
                  _CatalogGrid(
                    entries: data.lists[tab.key] ?? const <CatalogEntry>[],
                    isSerial: tab.isSerial,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              <String>[
                if (updated != null)
                  l.catalogUpdated(
                    '${updated.year}-${updated.month.toString().padLeft(2, '0')}'
                    '-${updated.day.toString().padLeft(2, '0')}',
                  ),
                if (!hasKinopoisk) l.catalogNoKinopoisk,
              ].join(' · '),
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogGrid extends StatelessWidget {
  const _CatalogGrid({required this.entries, required this.isSerial});

  final List<CatalogEntry> entries;
  final bool isSerial;

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
      itemCount: entries.length,
      itemBuilder: (BuildContext context, int index) => _CatalogCardView(
        key: ValueKey<String>('${entries[index].imdb}-${entries[index].title}'),
        rank: index + 1,
        entry: entries[index],
        isSerial: isSerial,
      ),
    );
  }
}

class _CatalogCardView extends ConsumerWidget {
  const _CatalogCardView({
    required this.rank,
    required this.entry,
    required this.isSerial,
    super.key,
  });

  final int rank;
  final CatalogEntry entry;
  final bool isSerial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CatalogCard? card = ref.watch(catalogCardProvider(entry)).valueOrNull;
    final String title = card?.title ?? entry.title;
    final String? poster = card?.posterUrl;
    final double? rating = entry.rating;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      onTap: () {
        final WatchQuery query = (
          title: title,
          originalTitle: entry.original.isEmpty ? null : entry.original,
          year: entry.year,
          isSerial: isSerial,
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
                Positioned(
                  left: AppSpacing.xs,
                  top: AppSpacing.xs,
                  child: _Badge(text: '$rank'),
                ),
                if (rating != null)
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
          if (entry.year != null)
            Text(
              '${entry.year}',
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
