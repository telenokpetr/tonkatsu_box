import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/constants/platform_features.dart';
import '../../../shared/extensions/snackbar_extension.dart';

const int _bufferBytes = 64 * 1024 * 1024;
const Duration _errorSnackDuration = Duration(seconds: 6);

// media_kit sizes its controls for a 28 px button. Desktop runs at 150% of
// that; a phone keeps 100% since its screen is already close to the eye.
const double _kBaseIcon = 28;
const double _kBaseTitle = 14;
const double _kBaseTime = 12;
const double _kBaseMargin = 16;
const double _kDesktopScale = 1.5;
const double _kMobileScale = 1;

class _Metrics {
  const _Metrics(this.scale);

  static const _Metrics desktop = _Metrics(_kDesktopScale);
  static const _Metrics mobile = _Metrics(_kMobileScale);

  final double scale;

  double get icon => _kBaseIcon * scale;
  double get title => _kBaseTitle * scale;
  double get time => _kBaseTime * scale;
  double get menuItemHeight => kMinInteractiveDimension * scale;
  double get menuMinWidth => 112 * scale;
  EdgeInsets get margin =>
      EdgeInsets.symmetric(horizontal: _kBaseMargin * scale);
}

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

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.url));
    if (!mounted) return;
    context.showSnack(S.of(context).watchLinkCopied, type: SnackType.success);
  }

  List<Widget> _topBar(S l, _Metrics m) => <Widget>[
    IconButton(
      icon: const Icon(Icons.arrow_back),
      iconSize: m.icon,
      color: Colors.white,
      onPressed: () => Navigator.of(context).pop(),
    ),
    Expanded(
      child: Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white, fontSize: m.title),
      ),
    ),
    IconButton(
      icon: const Icon(Icons.link),
      iconSize: m.icon,
      color: Colors.white,
      tooltip: l.watchCopyLink,
      onPressed: _copyLink,
    ),
  ];

  Widget _desktopControls(S l, _Metrics m) {
    final MaterialDesktopVideoControlsThemeData controls =
        MaterialDesktopVideoControlsThemeData(
          topButtonBar: _topBar(l, m),
          bottomButtonBar: <Widget>[
            const MaterialDesktopPlayOrPauseButton(),
            const MaterialDesktopVolumeButton(),
            MaterialDesktopPositionIndicator(
              style: TextStyle(
                height: 1.0,
                fontSize: m.time,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            _TracksButton(player: _player, metrics: m),
            const MaterialFullscreenButton(),
          ],
          buttonBarButtonSize: m.icon,
          buttonBarButtonColor: Colors.white,
          topButtonBarMargin: m.margin,
          bottomButtonBarMargin: m.margin,
          seekBarMargin: m.margin,
          seekBarHeight: 3.2 * m.scale,
          seekBarHoverHeight: 5.6 * m.scale,
          seekBarContainerHeight: 36 * m.scale,
          seekBarThumbSize: 12 * m.scale,
          volumeBarThumbSize: 12 * m.scale,
        );
    return MaterialDesktopVideoControlsTheme(
      normal: controls,
      fullscreen: controls,
      child: Video(controller: _controller),
    );
  }

  Widget _mobileControls(S l, _Metrics m) {
    final MaterialVideoControlsThemeData controls =
        MaterialVideoControlsThemeData(
          topButtonBar: _topBar(l, m),
          bottomButtonBar: <Widget>[
            MaterialPositionIndicator(
              style: TextStyle(
                height: 1.0,
                fontSize: m.time,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            _TracksButton(player: _player, metrics: m),
            const MaterialFullscreenButton(),
          ],
          buttonBarButtonSize: m.icon,
          buttonBarButtonColor: Colors.white,
          topButtonBarMargin: m.margin,
        );
    return MaterialVideoControlsTheme(
      normal: controls,
      fullscreen: controls,
      child: Video(controller: _controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: kIsMobile
          ? _mobileControls(l, _Metrics.mobile)
          : _desktopControls(l, _Metrics.desktop),
    );
  }
}

bool _isRealAudio(AudioTrack t) => t.id != 'auto' && t.id != 'no';

bool _isRealSubtitle(SubtitleTrack t) => t.id != 'auto' && t.id != 'no';

/// Audio and subtitle picker; a dubbed release usually carries several
/// dubs plus the original, and mpv starts on whichever the file flags.
class _TracksButton extends StatelessWidget {
  const _TracksButton({required this.player, required this.metrics});

  final Player player;
  final _Metrics metrics;

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
    final double height = metrics.menuItemHeight;
    return PopupMenuButton<Object>(
      icon: const Icon(Icons.subtitles_outlined, color: Colors.white),
      iconSize: metrics.icon,
      constraints: BoxConstraints(minWidth: metrics.menuMinWidth),
      tooltip: '${l.watchAudioTracks} / ${l.watchSubtitleTracks}',
      onSelected: (Object value) {
        if (value is AudioTrack) player.setAudioTrack(value);
        if (value is SubtitleTrack) player.setSubtitleTrack(value);
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Object>>[
        PopupMenuItem<Object>(
          enabled: false,
          height: height,
          child: _menuText(l.watchAudioTracks),
        ),
        for (int i = 0; i < audio.length; i++)
          CheckedPopupMenuItem<Object>(
            value: audio[i],
            height: height,
            checked: selected.audio.id == audio[i].id,
            child: _menuText(_label(l, i, audio[i].title, audio[i].language)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          enabled: false,
          height: height,
          child: _menuText(l.watchSubtitleTracks),
        ),
        CheckedPopupMenuItem<Object>(
          value: SubtitleTrack.no(),
          height: height,
          checked: selected.subtitle.id == 'no',
          child: _menuText(l.watchTrackOff),
        ),
        for (int i = 0; i < subtitles.length; i++)
          CheckedPopupMenuItem<Object>(
            value: subtitles[i],
            height: height,
            checked: selected.subtitle.id == subtitles[i].id,
            child: _menuText(
              _label(l, i, subtitles[i].title, subtitles[i].language),
            ),
          ),
      ],
    );
  }

  Widget _menuText(String text) =>
      Text(text, style: TextStyle(fontSize: metrics.title));
}
