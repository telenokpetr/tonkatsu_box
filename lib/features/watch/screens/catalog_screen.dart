import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/catalog_api.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/screen_app_bar.dart';
import '../catalog_shelves.dart';
import '../providers/watch_providers.dart';
import '../watch_query.dart';
import 'watch_screen.dart';

// Windows 11 dark palette and type: the catalog deliberately looks like a
// Windows app rather than the rest of Tonkatsu Box.
const String _kFont = 'Segoe UI';
const Color _kBackground = Color(0xFF202020);
const Color _kLayer = Color(0xFF2B2B2B);
const Color _kStroke = Color(0xFF3A3A3A);
const Color _kHover = Color(0x0FFFFFFF);
const Color _kSelected = Color(0x14FFFFFF);
const Color _kAccent = Color(0xFF60CDFF);
const Color _kTextPrimary = Color(0xFFFFFFFF);
const Color _kTextSecondary = Color(0xC5FFFFFF);
const Color _kTextTertiary = Color(0x8BFFFFFF);

const double _kCornerRadius = 8;
const double _kRailWidth = 260;
const double _kRailCompactWidth = 56;
const double _kRailBreakpoint = 760;
const double _kCardWidth = 160;
const double _kGridGap = 16;
const Duration _kHoverDuration = Duration(milliseconds: 120);

/// Rail sections; a divider is drawn between groups.
const List<List<String>> _kRailGroups = <List<String>>[
  <String>['recs'],
  <String>['trend_movies', 'trend_series', 'top_series'],
  <String>['cartoons', 'old_cartoons', 'soviet_cartoons'],
  <String>['anime', 'old_anime'],
  <String>['movies_top', 'series_top', 'movies_popular'],
  <String>['kp_movies_top', 'kp_series_top', 'kp_popular'],
];

IconData _shelfIcon(String id) => switch (id) {
  'recs' => Icons.auto_awesome_outlined,
  'trend_movies' => Icons.local_fire_department_outlined,
  'trend_series' => Icons.tv_outlined,
  'top_series' => Icons.star_outline,
  'cartoons' => Icons.toys_outlined,
  'old_cartoons' => Icons.history,
  'soviet_cartoons' => Icons.flag_outlined,
  'anime' => Icons.animation,
  'old_anime' => Icons.history_edu_outlined,
  'movies_top' => Icons.emoji_events_outlined,
  'series_top' => Icons.workspace_premium_outlined,
  'movies_popular' => Icons.trending_up,
  'kp_movies_top' => Icons.emoji_events_outlined,
  'kp_series_top' => Icons.workspace_premium_outlined,
  'kp_popular' => Icons.trending_up,
  _ => Icons.movie_outlined,
};

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
  String _selected = kShelfIds.first;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String text) => setState(() => _query = text.trim());

  void _select(String id) {
    _search.clear();
    setState(() {
      _selected = id;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final ThemeData base = Theme.of(context);
    final ThemeData theme = base.copyWith(
      scaffoldBackgroundColor: _kBackground,
      textTheme: base.textTheme.apply(
        fontFamily: _kFont,
        bodyColor: _kTextPrimary,
        displayColor: _kTextPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _kLayer,
        hintStyle: const TextStyle(fontFamily: _kFont, color: _kTextTertiary),
        prefixIconColor: _kTextTertiary,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_kCornerRadius),
          borderSide: const BorderSide(color: _kStroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_kCornerRadius),
          borderSide: const BorderSide(color: _kStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_kCornerRadius),
          borderSide: const BorderSide(color: _kAccent, width: 2),
        ),
      ),
    );
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: _kBackground,
        appBar: ScreenAppBar(title: l.catalogTitle),
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final bool compact = box.maxWidth < _kRailBreakpoint;
            return Row(
              children: <Widget>[
                _Rail(
                  selected: _query.isEmpty ? _selected : '',
                  compact: compact,
                  onSelect: _select,
                ),
                Expanded(
                  child: _Content(
                    controller: _search,
                    query: _query,
                    selected: _selected,
                    onSubmitted: _setQuery,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.selected,
    required this.compact,
    required this.onSelect,
  });

  final String selected;
  final bool compact;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    return Container(
      width: compact ? _kRailCompactWidth : _kRailWidth,
      color: _kBackground,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        children: <Widget>[
          for (int g = 0; g < _kRailGroups.length; g++) ...<Widget>[
            if (g > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Divider(height: 1, color: _kStroke),
              ),
            for (final String id in _kRailGroups[g])
              _RailItem(
                icon: _shelfIcon(id),
                label: _shelfLabel(l, id),
                selected: id == selected,
                compact: compact,
                onTap: () => onSelect(id),
              ),
          ],
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color fill = widget.selected
        ? _kSelected
        : _hover
        ? _kHover
        : Colors.transparent;
    final Widget row = Row(
      children: <Widget>[
        // The accent pill is Windows' mark of the current page.
        AnimatedContainer(
          duration: _kHoverDuration,
          width: 3,
          height: widget.selected ? 16 : 0,
          decoration: BoxDecoration(
            color: _kAccent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Icon(widget.icon, size: 18, color: _kTextPrimary),
        if (!widget.compact) ...<Widget>[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 14,
                color: _kTextPrimary,
              ),
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Tooltip(
            message: widget.compact ? widget.label : '',
            child: AnimatedContainer(
              duration: _kHoverDuration,
              height: 40,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(_kCornerRadius - 2),
              ),
              child: row,
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.controller,
    required this.query,
    required this.selected,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String query;
  final String selected;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final bool searching = query.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 4, right: 8, bottom: 8),
      decoration: BoxDecoration(
        color: _kLayer,
        borderRadius: BorderRadius.circular(_kCornerRadius + 4),
        border: Border.all(color: _kStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Text(
              searching ? query : _shelfLabel(l, selected),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: _kFont,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: _kTextPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontFamily: _kFont, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.catalogSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: searching
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            controller.clear();
                            onSubmitted('');
                          },
                        )
                      : null,
                ),
                onSubmitted: onSubmitted,
              ),
            ),
          ),
          Expanded(
            child: searching
                ? _SearchResults(query: query)
                : _ShelfView(id: selected),
          ),
        ],
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
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: _kFont,
            fontSize: 14,
            color: _kTextSecondary,
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _kCardWidth,
        mainAxisSpacing: _kGridGap,
        crossAxisSpacing: _kGridGap,
        childAspectRatio: 0.5,
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

class _CatalogCardView extends ConsumerStatefulWidget {
  const _CatalogCardView({required this.rank, required this.item, super.key});

  final int? rank;
  final CatalogItem item;

  @override
  ConsumerState<_CatalogCardView> createState() => _CatalogCardViewState();
}

class _CatalogCardViewState extends ConsumerState<_CatalogCardView> {
  bool _hover = false;

  void _open(String title) {
    final CatalogItem item = widget.item;
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
  }

  @override
  Widget build(BuildContext context) {
    final CatalogItem item = widget.item;
    final CatalogEntry? entry = item.entry;
    // Container entries carry no poster; TMDB shelves already have one.
    final CatalogCard? card = entry == null
        ? null
        : ref.watch(catalogCardProvider(entry)).valueOrNull;
    final String title = card?.title ?? item.title;
    final String? poster = item.posterUrl ?? card?.posterUrl;
    final double? rating = item.rating;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _open(title),
        child: AnimatedContainer(
          duration: _kHoverDuration,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _hover ? _kHover : Colors.transparent,
            borderRadius: BorderRadius.circular(_kCornerRadius),
            border: Border.all(color: _hover ? _kStroke : Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(_kCornerRadius - 2),
                      child: poster == null
                          ? const ColoredBox(color: _kBackground)
                          : CachedNetworkImage(
                              imageUrl: poster,
                              fit: BoxFit.cover,
                              errorWidget:
                                  (BuildContext c, String u, Object e) =>
                                      const ColoredBox(color: _kBackground),
                            ),
                    ),
                    if (widget.rank != null)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: _Badge(text: '${widget.rank}'),
                      ),
                    if (rating != null && rating > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: _Badge(text: rating.toStringAsFixed(1)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: _kFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kTextPrimary,
                ),
              ),
              if (item.year != null)
                Text(
                  '${item.year}',
                  style: const TextStyle(
                    fontFamily: _kFont,
                    fontSize: 12,
                    color: _kTextTertiary,
                  ),
                ),
            ],
          ),
        ),
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
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: _kFont,
            color: _kAccent,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
