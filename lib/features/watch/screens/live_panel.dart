import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/extensions/snackbar_extension.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/providers/watch_settings_provider.dart';
import '../play_stream.dart';
import '../stream_resolver.dart';
import '../watch_format.dart';
import '../youtube_feed.dart';

const Duration _kErrorSnack = Duration(seconds: 8);

String _favoritesKey(LiveService service) => 'watch_live_favs_${service.name}';

/// A link or channel box for YouTube, Twitch or Kick, with saved channels.
class LivePanel extends ConsumerStatefulWidget {
  const LivePanel({required this.service, super.key});

  final LiveService service;

  @override
  ConsumerState<LivePanel> createState() => _LivePanelState();
}

class _LivePanelState extends ConsumerState<LivePanel> {
  final TextEditingController _input = TextEditingController();
  late List<String> _favorites;
  bool _busy = false;
  YoutubeFeed _feed = YoutubeFeed.subscriptions;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  void initState() {
    super.initState();
    _favorites =
        _prefs.getStringList(_favoritesKey(widget.service)) ?? <String>[];
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _saveFavorites() =>
      _prefs.setStringList(_favoritesKey(widget.service), _favorites);

  Future<void> _addFavorite() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _favorites.contains(text)) return;
    setState(() => _favorites = <String>[..._favorites, text]);
    await _saveFavorites();
  }

  Future<void> _removeFavorite(String text) async {
    setState(
      () => _favorites = _favorites.where((String f) => f != text).toList(),
    );
    await _saveFavorites();
  }

  Future<void> _open(String text, {String? title}) async {
    final String input = text.trim();
    if (input.isEmpty || _busy) return;
    final S l = S.of(context);
    setState(() => _busy = true);
    try {
      final String url = await ref
          .read(streamResolverProvider)
          .resolve(
            widget.service,
            input,
            cookiesBrowser: ref.read(watchSettingsProvider).youtubeBrowser,
          );
      if (!mounted) return;
      await playStream(context, ref, url: url, title: title ?? input);
    } on StreamResolveException catch (e) {
      if (!mounted) return;
      final LiveTool? tool = e.missingTool;
      context.showSnack(
        tool != null
            ? l.liveToolMissing(tool.name, tool.wingetId)
            : l.liveResolveFailed(e.message),
        type: SnackType.error,
        duration: _kErrorSnack,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      context.showSnack(
        l.liveResolveFailed('$e'),
        type: SnackType.error,
        duration: _kErrorSnack,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final bool youtube = widget.service == LiveService.youtube;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: youtube
                          ? l.liveInputYoutube
                          : l.liveInputChannel,
                      prefixIcon: const Icon(Icons.link, size: 18),
                    ),
                    onSubmitted: _open,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: _busy ? null : () => _open(_input.text),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.liveOpen),
              ),
              IconButton(
                tooltip: l.liveSave,
                icon: const Icon(Icons.star_outline),
                onPressed: _addFavorite,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_favorites.isNotEmpty) ...<Widget>[
            Text(l.liveFavorites),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String fav in _favorites)
                  InputChip(
                    key: ValueKey<String>(fav),
                    label: Text(fav),
                    onPressed: () => _open(fav),
                    onDeleted: () => _removeFavorite(fav),
                  ),
              ],
            ),
          ],
          if (youtube) ...<Widget>[
            const SizedBox(height: 16),
            _YoutubeStatus(feed: _feed),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final YoutubeFeed feed in YoutubeFeed.values)
                  ChoiceChip(
                    label: Text(_feedLabel(l, feed)),
                    selected: _feed == feed,
                    onSelected: (_) => setState(() => _feed = feed),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _YoutubeFeedGrid(
                feed: _feed,
                onOpen: (YoutubeVideo v) => _open(v.url, title: v.title),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _feedLabel(S l, YoutubeFeed feed) => switch (feed) {
    YoutubeFeed.subscriptions => l.ytSubscriptions,
    YoutubeFeed.recommended => l.ytRecommended,
    YoutubeFeed.watchLater => l.ytWatchLater,
    YoutubeFeed.history => l.ytHistory,
  };
}

class _YoutubeFeedGrid extends ConsumerWidget {
  const _YoutubeFeedGrid({required this.feed, required this.onOpen});

  final YoutubeFeed feed;
  final ValueChanged<YoutubeVideo> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final S l = S.of(context);
    final String browser = ref.watch(watchSettingsProvider).youtubeBrowser;
    return ref
        .watch(youtubeFeedProvider(feed))
        .when(
          data: (List<YoutubeVideo> videos) => videos.isEmpty
              ? Center(child: Text(l.catalogEmpty))
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: videos.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _VideoCard(video: videos[index], onTap: onOpen),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  error is YoutubeFeedException && error.missingTool != null
                      ? l.liveToolMissing(
                          error.missingTool?.name ?? '',
                          error.missingTool?.wingetId ?? '',
                        )
                      : l.ytFeedFailed(
                          browser,
                          error is YoutubeFeedException
                              ? error.message
                              : '$error',
                        ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: <Widget>[
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: () => openYoutubeSignIn(browser),
                      child: Text(l.ytSignIn),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: () =>
                          ref.invalidate(youtubeFeedProvider(feed)),
                      child: Text(l.ytRetry),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
  }
}

/// Whether the account is connected, read off the feed that is showing.
class _YoutubeStatus extends ConsumerWidget {
  const _YoutubeStatus({required this.feed});

  final YoutubeFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final S l = S.of(context);
    final String browser = ref.watch(watchSettingsProvider).youtubeBrowser;
    final AsyncValue<List<YoutubeVideo>> state = ref.watch(
      youtubeFeedProvider(feed),
    );
    final (IconData, Color, String) view = state.when(
      data: (_) =>
          (Icons.check_circle, Colors.greenAccent, l.ytConnected(browser)),
      loading: () => (Icons.sync, Colors.white54, l.ytChecking),
      error: (Object e, StackTrace s) =>
          (Icons.error_outline, Colors.orangeAccent, l.ytNotConnected(browser)),
    );
    return Row(
      children: <Widget>[
        Icon(view.$1, size: 18, color: view.$2),
        const SizedBox(width: 8),
        Text(view.$3, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video, required this.onTap});

  final YoutubeVideo video;
  final ValueChanged<YoutubeVideo> onTap;

  @override
  Widget build(BuildContext context) {
    final int? seconds = video.durationSeconds;
    final String? thumb = video.thumbnail;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onTap(video),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: thumb == null
                      ? const ColoredBox(color: Colors.black26)
                      : CachedNetworkImage(
                          imageUrl: thumb,
                          fit: BoxFit.cover,
                          errorWidget: (BuildContext c, String u, Object e) =>
                              const ColoredBox(color: Colors.black26),
                        ),
                ),
                if (seconds != null)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        child: Text(
                          formatClock(Duration(seconds: seconds)),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if (video.channel != null)
            Text(
              video.channel ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
        ],
      ),
    );
  }
}
