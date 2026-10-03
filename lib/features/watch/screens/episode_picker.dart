import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/torrserver_api.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/theme/app_typography.dart';
import '../watch_episodes.dart';
import '../watch_format.dart';
import '../watch_progress.dart';

const double _kDialogWidth = 640;
const double _kDialogHeight = 580;

enum _RowAction { fromStart, markWatched, markUnwatched }

/// Season-by-season list of a torrent's files with what was watched and where
/// playback stopped; resolves to the chosen file, null when dismissed.
Future<TorrServerFile?> showEpisodePicker(
  BuildContext context, {
  required String hash,
  required String title,
  required List<EpisodeEntry> entries,
}) {
  return showDialog<TorrServerFile>(
    context: context,
    builder: (BuildContext dialogContext) =>
        EpisodePicker(hash: hash, title: title, entries: entries),
  );
}

class EpisodePicker extends ConsumerStatefulWidget {
  const EpisodePicker({
    required this.hash,
    required this.title,
    required this.entries,
    super.key,
  });

  final String hash;
  final String title;
  final List<EpisodeEntry> entries;

  @override
  ConsumerState<EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends ConsumerState<EpisodePicker> {
  int? _season;
  bool _seasonChosen = false;

  List<String> get _keys => <String>[
    for (final EpisodeEntry e in widget.entries)
      progressKey(widget.hash, e.file.path),
  ];

  List<int> get _seasons =>
      widget.entries
          .map((EpisodeEntry e) => e.id.season)
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();

  void _pick(TorrServerFile file) => Navigator.of(context).pop(file);

  void _onAction(_RowAction action, EpisodeEntry entry) {
    final WatchProgressNotifier notifier = ref.read(
      watchProgressProvider.notifier,
    );
    final String key = progressKey(widget.hash, entry.file.path);
    switch (action) {
      case _RowAction.fromStart:
        notifier.reset(key);
        _pick(entry.file);
      case _RowAction.markWatched:
        notifier.setWatched(key, watched: true);
      case _RowAction.markUnwatched:
        notifier.reset(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final Map<String, WatchProgress> progress = ref.watch(
      watchProgressProvider,
    );
    final List<String> keys = _keys;
    final int? resumeAt = continueIndex(keys, progress);
    final List<int> seasons = _seasons;
    if (!_seasonChosen && seasons.length > 1) {
      final int? hint = resumeAt == null
          ? null
          : widget.entries[resumeAt].id.season;
      _season = hint ?? seasons.first;
    }
    final bool filtered = seasons.length > 1 && _season != null;
    final List<int> visible = <int>[
      for (int i = 0; i < widget.entries.length; i++)
        if (!filtered || widget.entries[i].id.season == _season) i,
    ];

    return Dialog(
      child: SizedBox(
        width: _kDialogWidth,
        height: _kDialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                widget.title.isEmpty ? l.watchPickFile : widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.h3,
              ),
            ),
            if (resumeAt != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _ContinueButton(
                  label: l.watchContinue(
                    _title(l, widget.entries[resumeAt], seasons.length > 1),
                  ),
                  detail: _detail(l, progress[keys[resumeAt]]),
                  onPressed: () => _pick(widget.entries[resumeAt].file),
                ),
              ),
            if (seasons.length > 1)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  children: <Widget>[
                    for (final int season in seasons)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: ChoiceChip(
                          key: ValueKey<int>(season),
                          label: Text(l.watchSeason(season)),
                          selected: _season == season,
                          onSelected: (bool _) => setState(() {
                            _season = season;
                            _seasonChosen = true;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (BuildContext context, int row) {
                  final int i = visible[row];
                  final EpisodeEntry entry = widget.entries[i];
                  final WatchProgress? saved = progress[keys[i]];
                  return _EpisodeTile(
                    key: ValueKey<int>(entry.file.id),
                    title: _title(l, entry, false),
                    fileName: entry.file.name,
                    size: formatBytes(entry.file.length),
                    progress: saved,
                    highlighted: i == resumeAt,
                    detail: _detail(l, saved),
                    onTap: () => _pick(entry.file),
                    onAction: (_RowAction a) => _onAction(a, entry),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _title(S l, EpisodeEntry entry, bool withSeason) =>
      episodeLabel(l, entry.id, entry.file.name, withSeason: withSeason);

  String? _detail(S l, WatchProgress? saved) {
    final Duration? at = saved?.resumeAt;
    if (saved == null || at == null) return null;
    return l.watchStoppedAt(formatClock(at), formatClock(saved.duration));
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.label,
    required this.detail,
    required this.onPressed,
  });

  final String label;
  final String? detail;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 56),
        alignment: Alignment.centerLeft,
      ),
      onPressed: onPressed,
      child: Row(
        children: <Widget>[
          const Icon(Icons.play_arrow),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (detail != null)
                  Text(detail ?? '', style: AppTypography.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.title,
    required this.fileName,
    required this.size,
    required this.progress,
    required this.highlighted,
    required this.detail,
    required this.onTap,
    required this.onAction,
    super.key,
  });

  final String title;
  final String fileName;
  final String size;
  final WatchProgress? progress;
  final bool highlighted;
  final String? detail;
  final VoidCallback onTap;
  final void Function(_RowAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final bool watched = progress?.watched ?? false;
    final double fraction = progress?.fraction ?? 0;
    return ListTile(
      selected: highlighted,
      onTap: onTap,
      leading: Icon(
        watched ? Icons.check_circle : Icons.play_circle_outline,
        color: watched ? AppColors.success : null,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: watched
            ? AppTypography.body.copyWith(color: AppColors.textTertiary)
            : AppTypography.body,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title == fileName ? size : '$fileName · $size',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption,
          ),
          if (detail != null) ...<Widget>[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: fraction, minHeight: 3),
            const SizedBox(height: 2),
            Text(detail ?? '', style: AppTypography.caption),
          ],
        ],
      ),
      trailing: PopupMenuButton<_RowAction>(
        onSelected: onAction,
        itemBuilder: (BuildContext context) => <PopupMenuEntry<_RowAction>>[
          if (detail != null)
            PopupMenuItem<_RowAction>(
              value: _RowAction.fromStart,
              child: Text(l.watchFromStart),
            ),
          if (!watched)
            PopupMenuItem<_RowAction>(
              value: _RowAction.markWatched,
              child: Text(l.watchMarkWatched),
            ),
          if (watched || detail != null)
            PopupMenuItem<_RowAction>(
              value: _RowAction.markUnwatched,
              child: Text(l.watchMarkUnwatched),
            ),
        ],
      ),
    );
  }
}
