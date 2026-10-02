import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/constants/platform_features.dart';
import '../../../shared/extensions/snackbar_extension.dart';
import '../player/player_overlay.dart';
import '../player/player_state.dart';

const int _bufferBytes = 64 * 1024 * 1024;
const Duration _errorSnackDuration = Duration(seconds: 6);

class PlayerItem {
  const PlayerItem({required this.url, required this.title});

  final String url;
  final String title;
}

/// Full-window libmpv player. Several items play as a playlist starting at
/// [startIndex], so a season carries on to the next episode by itself.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.items, this.startIndex = 0, super.key});

  PlayerScreen.single({required String url, required String title, Key? key})
    : this(
        items: <PlayerItem>[PlayerItem(url: url, title: title)],
        key: key,
      );

  final List<PlayerItem> items;
  final int startIndex;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Big read-ahead: a torrent stalls for a second at a time, and mpv's
  // default cache then runs dry and rebuffers.
  late final Player _player = Player(
    configuration: const PlayerConfiguration(bufferSize: _bufferBytes),
  );
  late final VideoController _controller = VideoController(_player);
  StreamSubscription<String>? _errors;

  @override
  void initState() {
    super.initState();
    _errors = _player.stream.error.listen(_onError);
    _player.open(
      Playlist(<Media>[
        for (final PlayerItem i in widget.items) Media(i.url),
      ], index: widget.startIndex.clamp(0, widget.items.length - 1)),
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
    _errors?.cancel();
    _player.dispose();
    if (kIsMobile) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
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
class _PlayerBinding extends StatefulWidget {
  const _PlayerBinding({required this.player, required this.items});

  final Player player;
  final List<PlayerItem> items;

  @override
  State<_PlayerBinding> createState() => _PlayerBindingState();
}

class _PlayerBindingState extends State<_PlayerBinding> {
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
