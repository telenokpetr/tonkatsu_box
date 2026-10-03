import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/constants/platform_features.dart';
import '../../../shared/extensions/snackbar_extension.dart';
import '../player/player_overlay.dart';
import '../player/player_state.dart';
import '../watch_episodes.dart';
import '../watch_format.dart';
import '../watch_progress.dart';

// Whole episode in memory: a torrent that keeps up is read to the end, so
// seeking and pausing never wait on the network again.
const int _bufferBytes = 2 * 1024 * 1024 * 1024;
const String _readAheadSeconds = '14400';
const Duration _errorSnackDuration = Duration(seconds: 6);
const Duration _saveEvery = Duration(seconds: 5);

final Logger _log = Logger('Player');

class PlayerItem {
  const PlayerItem({
    required this.url,
    required this.title,
    this.progressKey,
    this.path,
  });

  final String url;
  final String title;

  /// Where the stopping point is stored; null plays without remembering.
  final String? progressKey;

  /// Path inside the torrent, used to read the season and episode.
  final String? path;
}

/// Full-window libmpv player. Several items play as a playlist starting at
/// [startIndex], so a season carries on to the next episode by itself.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({required this.items, this.startIndex = 0, super.key});

  PlayerScreen.single({required String url, required String title, Key? key})
    : this(
        items: <PlayerItem>[PlayerItem(url: url, title: title)],
        key: key,
      );

  final List<PlayerItem> items;
  final int startIndex;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(bufferSize: _bufferBytes),
  );
  late final VideoController _controller = VideoController(_player);
  late final WatchProgressNotifier _progress = ref.read(
    watchProgressProvider.notifier,
  );
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  Timer? _saveTimer;
  int _index = 0;
  Duration? _pendingResume;
  ({int index, Duration position, Duration duration})? _snapshot;

  @override
  void initState() {
    super.initState();
    _index = widget.startIndex.clamp(0, widget.items.length - 1);
    _pendingResume = _resumeFor(_index);
    final PlayerStream s = _player.stream;
    _subscriptions
      ..add(s.error.listen(_onError))
      ..add(s.playlist.listen(_onPlaylist))
      ..add(s.position.listen(_onPosition))
      ..add(s.duration.listen(_onDuration));
    _saveTimer = Timer.periodic(_saveEvery, (Timer _) => _flush());
    _tune();
    _player.open(
      Playlist(<Media>[
        for (final PlayerItem i in widget.items) Media(i.url),
      ], index: _index),
    );
    if (kIsMobile) {
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    _flush();
    _saveTimer?.cancel();
    for (final StreamSubscription<Object?> sub in _subscriptions) {
      sub.cancel();
    }
    _player.dispose();
    if (kIsMobile) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _tune() async {
    final PlatformPlayer? platform = _player.platform;
    if (platform is! NativePlayer) return;
    for (final String name in <String>[
      'demuxer-readahead-secs',
      'cache-secs',
    ]) {
      try {
        await platform.setProperty(name, _readAheadSeconds);
      } on Object catch (e) {
        _log.warning('mpv rejected $name: $e');
      }
    }
  }

  Duration? _resumeFor(int index) {
    final String? key = widget.items[index].progressKey;
    return key == null ? null : ref.read(watchProgressProvider)[key]?.resumeAt;
  }

  void _onPlaylist(Playlist playlist) {
    final int next = playlist.index.clamp(0, widget.items.length - 1);
    if (next == _index) return;
    _flush();
    _snapshot = null;
    _index = next;
    _pendingResume = _resumeFor(next);
  }

  void _onPosition(Duration position) {
    final Duration duration = _player.state.duration;
    if (position <= Duration.zero ||
        duration <= Duration.zero ||
        _pendingResume != null) {
      return;
    }
    _snapshot = (index: _index, position: position, duration: duration);
  }

  void _onDuration(Duration duration) {
    final Duration? resume = _pendingResume;
    if (resume == null || duration <= Duration.zero || !mounted) return;
    _pendingResume = null;
    _player.seek(resume);
    context.showSnack(
      S.of(context).watchResumedAt(formatClock(resume)),
      type: SnackType.info,
    );
  }

  void _flush() {
    final ({int index, Duration position, Duration duration})? snap = _snapshot;
    if (snap == null) return;
    final String? key = widget.items[snap.index].progressKey;
    if (key == null) return;
    _progress.record(key, snap.position, snap.duration);
  }

  void _onError(String message) {
    if (!mounted || message.isEmpty) return;
    context.showSnack(
      S.of(context).watchPlayerError(message),
      type: SnackType.error,
      duration: _errorSnackDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Video(
        controller: _controller,
        controls: (VideoState state) =>
            _PlayerBinding(player: _player, items: widget.items),
      ),
    );
  }
}

/// Feeds the control panel from the libmpv player and maps its buttons back.
class _PlayerBinding extends ConsumerStatefulWidget {
  const _PlayerBinding({required this.player, required this.items});

  final Player player;
  final List<PlayerItem> items;

  @override
  ConsumerState<_PlayerBinding> createState() => _PlayerBindingState();
}

class _PlayerBindingState extends ConsumerState<_PlayerBinding> {
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  Player get _player => widget.player;

  @override
  void initState() {
    super.initState();
    final PlayerStream s = _player.stream;
    for (final Stream<Object?> stream in <Stream<Object?>>[
      s.position,
      s.duration,
      s.buffer,
      s.playing,
      s.buffering,
      s.volume,
      s.rate,
      s.playlist,
      s.tracks,
      s.track,
    ]) {
      _subscriptions.add(
        stream.listen((Object? _) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final StreamSubscription<Object?> sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  int get _index =>
      _player.state.playlist.index.clamp(0, widget.items.length - 1);

  String _label(S l, int i, String? title, String? language) {
    final List<String> parts = <String>[
      if (title != null && title.isNotEmpty) title,
      if (language != null && language.isNotEmpty) language,
    ];
    return parts.isEmpty ? l.watchTrackNumber(i + 1) : parts.join(' · ');
  }

  List<EpisodeOption> _episodes(S l, PlayerState st) {
    if (widget.items.length < 2) return const <EpisodeOption>[];
    final Map<String, WatchProgress> progress = ref.watch(
      watchProgressProvider,
    );
    final List<EpisodeId> ids = <EpisodeId>[
      for (final PlayerItem i in widget.items) parseEpisode(i.path ?? i.title),
    ];
    final bool manySeasons =
        ids.map((EpisodeId id) => id.season).whereType<int>().toSet().length >
        1;
    return <EpisodeOption>[
      for (int i = 0; i < widget.items.length; i++)
        () {
          final String? key = widget.items[i].progressKey;
          final WatchProgress? saved = key == null ? null : progress[key];
          final bool current = i == _index;
          final double live = st.duration > Duration.zero
              ? st.position.inSeconds / st.duration.inSeconds
              : 0;
          return EpisodeOption(
            title: episodeLabel(
              l,
              ids[i],
              widget.items[i].title,
              withSeason: manySeasons,
            ),
            fraction: current
                ? live.clamp(0, 1).toDouble()
                : saved?.fraction ?? 0,
            watched: saved?.watched ?? false,
            current: current,
          );
        }(),
    ];
  }

  PlayerView _view(S l) {
    final PlayerState st = _player.state;
    final List<AudioTrack> audio = st.tracks.audio
        .where((AudioTrack t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final List<SubtitleTrack> subs = st.tracks.subtitle
        .where((SubtitleTrack t) => t.id != 'auto' && t.id != 'no')
        .toList();
    return PlayerView(
      title: widget.items[_index].title,
      position: st.position,
      duration: st.duration,
      buffered: st.buffer,
      playing: st.playing,
      buffering: st.buffering,
      volume: st.volume,
      rate: st.rate,
      audio: <TrackOption>[
        for (int i = 0; i < audio.length; i++)
          TrackOption(
            id: audio[i].id,
            label: _label(l, i, audio[i].title, audio[i].language),
            selected: st.track.audio.id == audio[i].id,
          ),
      ],
      subtitles: subs.isEmpty
          ? const <TrackOption>[]
          : <TrackOption>[
              TrackOption(
                id: 'no',
                label: l.watchTrackOff,
                selected: st.track.subtitle.id == 'no',
              ),
              for (int i = 0; i < subs.length; i++)
                TrackOption(
                  id: subs[i].id,
                  label: _label(l, i, subs[i].title, subs[i].language),
                  selected: st.track.subtitle.id == subs[i].id,
                ),
            ],
      hasPrevious: _index > 0,
      hasNext: _index < widget.items.length - 1,
      fullscreen: isFullscreen(context),
      episodes: _episodes(l, st),
    );
  }

  PlayerActions _actions() {
    return PlayerActions(
      togglePlay: _player.playOrPause,
      seek: _player.seek,
      setVolume: _player.setVolume,
      setRate: _player.setRate,
      selectAudio: (String id) {
        for (final AudioTrack t in _player.state.tracks.audio) {
          if (t.id == id) _player.setAudioTrack(t);
        }
      },
      selectSubtitle: (String id) {
        if (id == 'no') {
          _player.setSubtitleTrack(SubtitleTrack.no());
          return;
        }
        for (final SubtitleTrack t in _player.state.tracks.subtitle) {
          if (t.id == id) _player.setSubtitleTrack(t);
        }
      },
      selectEpisode: _player.jump,
      previous: _player.previous,
      next: _player.next,
      toggleFullscreen: () => toggleFullscreen(context),
      exitFullscreen: () => exitFullscreen(context),
      back: () {
        if (isFullscreen(context)) {
          exitFullscreen(context);
        } else {
          Navigator.of(context).maybePop();
        }
      },
      copyLink: () async {
        await Clipboard.setData(ClipboardData(text: widget.items[_index].url));
        if (!mounted) return;
        context.showSnack(
          S.of(context).watchLinkCopied,
          type: SnackType.success,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    return PlayerOverlay(view: _view(l), actions: _actions());
  }
}
