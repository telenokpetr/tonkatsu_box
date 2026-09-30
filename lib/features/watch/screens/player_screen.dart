import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/extensions/snackbar_extension.dart';

const int _bufferBytes = 64 * 1024 * 1024;
const Duration _errorSnackDuration = Duration(seconds: 6);

/// Full-window libmpv player for a TorrServer stream URL.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.url, required this.title, super.key});

  final String url;
  final String title;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Big read-ahead: a torrent stalls for a second at a time, and mpv's
  // default cache then runs dry and rebuffers.
  late final Player _player = Player(
    configuration: PlayerConfiguration(
      title: widget.title,
      bufferSize: _bufferBytes,
    ),
  );
  late final VideoController _controller = VideoController(_player);
  StreamSubscription<String>? _errors;

  @override
  void initState() {
    super.initState();
    _errors = _player.stream.error.listen(_onError);
    _player.open(Media(widget.url));
  }

  @override
  void dispose() {
    _errors?.cancel();
    _player.dispose();
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

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    context.showSnack(S.of(context).watchLinkCopied, type: SnackType.success);
  }

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final List<Widget> topBar = <Widget>[
      BackButton(
        color: Colors.white,
        onPressed: () => Navigator.of(context).pop(),
      ),
      Expanded(
        child: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.link, color: Colors.white),
        tooltip: l.watchCopyLink,
        onPressed: _copyLink,
      ),
    ];
    final List<Widget> bottomBar = <Widget>[
      const MaterialDesktopPlayOrPauseButton(),
      const MaterialDesktopVolumeButton(),
      const MaterialDesktopPositionIndicator(),
      const Spacer(),
      _TracksButton(player: _player),
      const MaterialFullscreenButton(),
    ];
    final MaterialDesktopVideoControlsThemeData controls =
        MaterialDesktopVideoControlsThemeData(
          topButtonBar: topBar,
          bottomButtonBar: bottomBar,
        );

    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialDesktopVideoControlsTheme(
        normal: controls,
        fullscreen: controls,
        child: Video(controller: _controller),
      ),
    );
  }
}

bool _isRealAudio(AudioTrack t) => t.id != 'auto' && t.id != 'no';

bool _isRealSubtitle(SubtitleTrack t) => t.id != 'auto' && t.id != 'no';

/// Audio and subtitle picker; a dubbed release usually carries several
/// dubs plus the original, and mpv starts on whichever the file flags.
class _TracksButton extends StatelessWidget {
  const _TracksButton({required this.player});

  final Player player;

  String _label(S l, int index, String? title, String? language) {
    final List<String> parts = <String>[
      if (title != null && title.isNotEmpty) title,
      if (language != null && language.isNotEmpty) language,
    ];
    return parts.isEmpty ? l.watchTrackNumber(index + 1) : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (BuildContext context, AsyncSnapshot<Tracks> snapshot) {
        final Tracks tracks = snapshot.data ?? player.state.tracks;
        final List<AudioTrack> audio = tracks.audio
            .where(_isRealAudio)
            .toList();
        final List<SubtitleTrack> subtitles = tracks.subtitle
            .where(_isRealSubtitle)
            .toList();
        if (audio.length < 2 && subtitles.isEmpty) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<Track>(
          stream: player.stream.track,
          initialData: player.state.track,
          builder: (BuildContext context, AsyncSnapshot<Track> current) {
            final Track selected = current.data ?? player.state.track;
            return _menu(context, audio, subtitles, selected);
          },
        );
      },
    );
  }

  Widget _menu(
    BuildContext context,
    List<AudioTrack> audio,
    List<SubtitleTrack> subtitles,
    Track selected,
  ) {
    final S l = S.of(context);
    return PopupMenuButton<Object>(
      icon: const Icon(Icons.subtitles_outlined, color: Colors.white),
      tooltip: '${l.watchAudioTracks} / ${l.watchSubtitleTracks}',
      onSelected: (Object value) {
        if (value is AudioTrack) player.setAudioTrack(value);
        if (value is SubtitleTrack) player.setSubtitleTrack(value);
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Object>>[
        PopupMenuItem<Object>(enabled: false, child: Text(l.watchAudioTracks)),
        for (int i = 0; i < audio.length; i++)
          CheckedPopupMenuItem<Object>(
            value: audio[i],
            checked: selected.audio.id == audio[i].id,
            child: Text(_label(l, i, audio[i].title, audio[i].language)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          enabled: false,
          child: Text(l.watchSubtitleTracks),
        ),
        CheckedPopupMenuItem<Object>(
          value: SubtitleTrack.no(),
          checked: selected.subtitle.id == 'no',
          child: Text(l.watchTrackOff),
        ),
        for (int i = 0; i < subtitles.length; i++)
          CheckedPopupMenuItem<Object>(
            value: subtitles[i],
            checked: selected.subtitle.id == subtitles[i].id,
            child: Text(
              _label(l, i, subtitles[i].title, subtitles[i].language),
            ),
          ),
      ],
    );
  }
}
