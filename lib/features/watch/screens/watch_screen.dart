import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/jacred_api.dart';
import '../../../core/api/torrserver_api.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/constants/platform_features.dart';
import '../../../shared/extensions/snackbar_extension.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_typography.dart';
import '../../../shared/widgets/screen_app_bar.dart';
import '../../settings/providers/watch_settings_provider.dart';
import '../../settings/screens/watch_settings_screen.dart';
import '../providers/watch_providers.dart';
import '../external_player.dart';
import '../watch_episodes.dart';
import '../watch_progress.dart';
import '../watch_format.dart';
import '../watch_query.dart';
import 'episode_picker.dart';
import 'player_screen.dart';

const Duration _errorSnackDuration = Duration(seconds: 6);

enum _AddAction { pasteMagnet, pickFile }

/// Torrent picker: searches JacRed for [query], hands the chosen magnet to
/// TorrServer and opens the stream in VLC, or the built-in player.
class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({required this.query, super.key});

  final WatchQuery query;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  late WatchQuery _query = widget.query;
  late final TextEditingController _searchController = TextEditingController(
    text: widget.query.title,
  );
  bool _isStarting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch(String text) {
    final String title = text.trim();
    if (title.isEmpty) return;
    if (isMagnetLink(title)) {
      _searchController.text = _query.title;
      _play((TorrServerApi api) => api.addTorrent(title));
      return;
    }
    // A typed query is free text: the original title and year of the card
    // would only narrow it back to the old results.
    final bool unchanged = title == widget.query.title;
    setState(() {
      _query = (
        title: title,
        originalTitle: unchanged ? widget.query.originalTitle : null,
        year: unchanged ? widget.query.year : null,
        isSerial: widget.query.isSerial,
      );
    });
  }

  Future<void> _start(JacRedTorrent torrent) {
    return _play(
      (TorrServerApi api) =>
          api.addTorrent(torrent.magnet, title: torrent.title),
    );
  }

  Future<void> _pasteMagnet() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (!isMagnetLink(text)) {
      context.showSnack(
        S.of(context).watchNoMagnetInClipboard,
        type: SnackType.error,
      );
      return;
    }
    await _play((TorrServerApi api) => api.addTorrent(text));
  }

  Future<void> _pickTorrentFile() async {
    // Android has no MIME type for .torrent, so a filtered picker would hide
    // every file there; TorrServer rejects a wrong file anyway.
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: kIsMobile ? FileType.any : FileType.custom,
      allowedExtensions: kIsMobile ? null : const <String>['torrent'],
      withData: true,
    );
    final PlatformFile? picked = result?.files.firstOrNull;
    final Uint8List? bytes = picked?.bytes;
    if (picked == null || bytes == null || !mounted) return;
    await _play(
      (TorrServerApi api) => api.addTorrentFile(bytes, fileName: picked.name),
    );
  }

  Future<void> _play(
    Future<TorrServerTorrent> Function(TorrServerApi api) add,
  ) async {
    if (_isStarting) return;
    final S l = S.of(context);
    final TorrServerApi api = ref.read(torrServerApiProvider);
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    setState(() => _isStarting = true);
    try {
      final TorrServerTorrent added = await add(api);
      final TorrServerTorrent ready = added.files.isNotEmpty
          ? added
          : await api.waitForFiles(added.hash);
      if (!mounted) return;

      final List<EpisodeEntry> episodes = orderEpisodes(ready.videoFiles);
      final List<TorrServerFile> videos = <TorrServerFile>[
        for (final EpisodeEntry e in episodes) e.file,
      ];
      if (videos.isEmpty) {
        context.showSnack(
          l.watchNoVideoFiles,
          type: SnackType.error,
          duration: _errorSnackDuration,
        );
        return;
      }
      final TorrServerFile? file = videos.length == 1
          ? videos.first
          : await showEpisodePicker(
              context,
              hash: ready.hash,
              title: ready.title,
              entries: episodes,
            );
      if (file == null || !mounted) return;

      final WatchPlayer choice = ref.read(watchSettingsProvider).player;
      if (choice != WatchPlayer.builtIn) {
        final bool opened = await ref
            .read(externalPlayerProvider)
            .launch(
              choice: choice,
              urls: <String>[
                for (final TorrServerFile f in videos) api.streamUrl(ready, f),
              ],
              titles: <String>[for (final TorrServerFile f in videos) f.name],
              start: videos.indexOf(file),
            );
        if (opened) return;
        if (!mounted) return;
        context.showSnack(l.watchVlcMissing, type: SnackType.error);
      }

      await navigator.push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => PlayerScreen(
            items: <PlayerItem>[
              for (final TorrServerFile f in videos)
                PlayerItem(
                  url: api.streamUrl(ready, f),
                  title: f.name,
                  progressKey: progressKey(ready.hash, f.path),
                  path: f.path,
                ),
            ],
            startIndex: videos.indexOf(file),
          ),
        ),
      );
    } on TorrServerApiException catch (e) {
      if (!mounted) return;
      context.showSnack(
        l.watchStartFailed(e.message),
        type: SnackType.error,
        duration: _errorSnackDuration,
      );
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            const Scaffold(body: SafeArea(child: WatchSettingsScreen())),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final bool configured = ref.watch(watchSettingsProvider).isConfigured;

    return Scaffold(
      appBar: ScreenAppBar(title: '${l.watchAction} — ${widget.query.title}'),
      body: Stack(
        children: <Widget>[
          if (configured) _buildSearch(l) else _buildNotConfigured(l),
          if (_isStarting) _buildStartingOverlay(l),
        ],
      ),
    );
  }

  Widget _buildNotConfigured(S l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(l.watchNotConfigured, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSpacing.buttonHeightCompact),
            ),
            onPressed: _openSettings,
            child: Text(l.watchOpenSettings),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch(S l) {
    final AsyncValue<List<JacRedTorrent>> results = ref.watch(
      watchResultsProvider(_query),
    );
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l.watchSearchHint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onSubmitted: _submitSearch,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _buildAddButton(l),
            ],
          ),
        ),
        Expanded(
          child: results.when(
            data: (List<JacRedTorrent> torrents) => torrents.isEmpty
                ? Center(child: Text(l.watchNoResults))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    itemCount: torrents.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _TorrentTile(
                          torrent: torrents[index],
                          onTap: () => _start(torrents[index]),
                        ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  l.watchSearchFailed(
                    error is JacRedApiException
                        ? error.message
                        : error.toString(),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddButton(S l) {
    return PopupMenuButton<_AddAction>(
      icon: const Icon(Icons.add_link),
      tooltip: l.watchAddTorrent,
      onSelected: (_AddAction action) => switch (action) {
        _AddAction.pasteMagnet => _pasteMagnet(),
        _AddAction.pickFile => _pickTorrentFile(),
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_AddAction>>[
        PopupMenuItem<_AddAction>(
          value: _AddAction.pasteMagnet,
          child: ListTile(
            leading: const Icon(Icons.content_paste),
            title: Text(l.watchPasteMagnet),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_AddAction>(
          value: _AddAction.pickFile,
          child: ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(l.watchPickTorrentFile),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildStartingOverlay(S l) {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.barrier,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text(l.watchConnectingPeers),
            ],
          ),
        ),
      ),
    );
  }
}

class _TorrentTile extends StatelessWidget {
  const _TorrentTile({required this.torrent, required this.onTap});

  final JacRedTorrent torrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? tracker = torrent.tracker;
    final List<String> meta = <String>[
      if (torrent.quality != null) '${torrent.quality}p',
      formatBytes(torrent.sizeBytes),
      if (tracker != null && tracker.isNotEmpty) tracker,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      torrent.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      meta.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.arrow_upward,
                        size: 14,
                        color: AppColors.success,
                      ),
                      Text(
                        '${torrent.seeders}',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${torrent.peers}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
