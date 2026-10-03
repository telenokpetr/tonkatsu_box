import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../watch_format.dart';
import 'player_state.dart';

const Color _kAccent = Color(0xFF60CDFF);
const double _kIconSize = 34;
const double _kPlayIconSize = 46;
const double _kTimeSize = 16;
const double _kTitleSize = 20;
const Duration _kFade = Duration(milliseconds: 180);
const Duration _kSeekStep = Duration(seconds: 10);
const Duration _kSeekBigStep = Duration(seconds: 60);
const double _kVolumeStep = 5;
const double _kVolumeSliderWidth = 120;

/// The control panel drawn over the video: top bar, centre spinner, seek bar
/// and buttons, shortcuts, and auto-hide. Plain Flutter widgets only, so what
/// the tests render is what the window shows.
class PlayerOverlay extends StatefulWidget {
  const PlayerOverlay({
    required this.view,
    required this.actions,
    this.hideAfter = const Duration(seconds: 3),
    super.key,
  });

  final PlayerView view;
  final PlayerActions actions;
  final Duration hideAfter;

  @override
  State<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends State<PlayerOverlay> {
  bool _visible = true;
  bool _panel = false;
  Timer? _timer;
  double _lastVolume = 100;

  PlayerView get _view => widget.view;
  PlayerActions get _actions => widget.actions;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(widget.hideAfter, () {
      if (mounted && _view.playing && !_panel) setState(() => _visible = false);
    });
  }

  Duration _clamped(Duration d) {
    if (d < Duration.zero) return Duration.zero;
    if (_view.duration > Duration.zero && d > _view.duration) {
      return _view.duration;
    }
    return d;
  }

  void _seekBy(Duration delta) =>
      _actions.seek(_clamped(_view.position + delta));

  void _volumeBy(double delta) =>
      _actions.setVolume((_view.volume + delta).clamp(0, 100).toDouble());

  void _toggleMute() {
    if (_view.volume > 0) {
      _lastVolume = _view.volume;
      _actions.setVolume(0);
    } else {
      _actions.setVolume(_lastVolume);
    }
  }

  bool get _hasEpisodes =>
      _view.episodes.length > 1 && _actions.selectEpisode != null;

  void _togglePanel() {
    if (!_hasEpisodes) return;
    setState(() => _panel = !_panel);
    _show();
  }

  void _cycle(List<TrackOption> options, void Function(String id) select) {
    final TrackOption? next = nextTrack(options);
    if (next != null) select(next.id);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    final bool big = HardwareKeyboard.instance.isControlPressed;
    _show();
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      if (event is KeyDownEvent) _actions.togglePlay();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-(big ? _kSeekBigStep : _kSeekStep));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(big ? _kSeekBigStep : _kSeekStep);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _volumeBy(_kVolumeStep);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _volumeBy(-_kVolumeStep);
    } else if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.keyF ||
        key == LogicalKeyboardKey.f11) {
      _actions.toggleFullscreen();
    } else if (key == LogicalKeyboardKey.keyE) {
      _togglePanel();
    } else if (key == LogicalKeyboardKey.escape) {
      if (_panel) {
        setState(() => _panel = false);
      } else {
        _view.fullscreen ? _actions.exitFullscreen() : _actions.back();
      }
    } else if (key == LogicalKeyboardKey.keyN ||
        key == LogicalKeyboardKey.pageDown) {
      if (_view.hasNext) _actions.next();
    } else if (key == LogicalKeyboardKey.keyP ||
        key == LogicalKeyboardKey.pageUp) {
      if (_view.hasPrevious) _actions.previous();
    } else if (key == LogicalKeyboardKey.keyA) {
      _cycle(_view.audio, _actions.selectAudio);
    } else if (key == LogicalKeyboardKey.keyS) {
      _cycle(_view.subtitles, _actions.selectSubtitle);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: _visible ? SystemMouseCursors.basic : SystemMouseCursors.none,
        onHover: (_) => _show(),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _actions.togglePlay();
                _show();
              },
              onDoubleTap: _actions.toggleFullscreen,
            ),
            if (_view.buffering)
              const Center(child: CircularProgressIndicator(color: _kAccent)),
            AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: _kFade,
              child: IgnorePointer(
                ignoring: !_visible,
                child: Column(
                  children: <Widget>[
                    _TopBar(view: _view, actions: _actions),
                    const Spacer(),
                    _BottomBar(
                      view: _view,
                      actions: _actions,
                      onMute: _toggleMute,
                      onEpisodes: _hasEpisodes ? _togglePanel : null,
                    ),
                  ],
                ),
              ),
            ),
            if (_panel && _hasEpisodes)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 84, 0, 130),
                  child: _EpisodePanel(
                    episodes: _view.episodes,
                    onSelect: (int i) {
                      _actions.selectEpisode?.call(i);
                      setState(() => _panel = false);
                    },
                    onClose: () => setState(() => _panel = false),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.fromTop, required this.child});

  final bool fromTop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
          end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
          colors: const <Color>[Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: child,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.view, required this.actions});

  final PlayerView view;
  final PlayerActions actions;

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    return _Fade(
      fromTop: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        child: Row(
          children: <Widget>[
            _IconBtn(
              icon: Icons.arrow_back,
              tooltip: '',
              onPressed: actions.back,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                view.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: _kTitleSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _IconBtn(
              icon: Icons.link,
              tooltip: l.watchCopyLink,
              onPressed: actions.copyLink,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = _kIconSize,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: size,
      color: Colors.white,
      disabledColor: Colors.white30,
      tooltip: tooltip.isEmpty ? null : tooltip,
      onPressed: onPressed,
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.view,
    required this.actions,
    required this.onMute,
    this.onEpisodes,
  });

  final PlayerView view;
  final PlayerActions actions;
  final VoidCallback onMute;
  final VoidCallback? onEpisodes;

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    return _Fade(
      fromTop: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SeekBar(view: view, onSeek: actions.seek),
            Row(
              children: <Widget>[
                _IconBtn(
                  icon: Icons.skip_previous,
                  tooltip: '',
                  onPressed: view.hasPrevious ? actions.previous : null,
                ),
                _IconBtn(
                  icon: view.playing ? Icons.pause : Icons.play_arrow,
                  tooltip: '',
                  size: _kPlayIconSize,
                  onPressed: actions.togglePlay,
                ),
                _IconBtn(
                  icon: Icons.skip_next,
                  tooltip: '',
                  onPressed: view.hasNext ? actions.next : null,
                ),
                _IconBtn(
                  icon: view.volume <= 0 ? Icons.volume_off : Icons.volume_up,
                  tooltip: '',
                  onPressed: onMute,
                ),
                SizedBox(
                  width: _kVolumeSliderWidth,
                  child: _thin(
                    Slider(
                      value: view.volume.clamp(0, 100).toDouble(),
                      max: 100,
                      onChanged: actions.setVolume,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${formatClock(view.position)} / ${formatClock(view.duration)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: _kTimeSize,
                  ),
                ),
                const Spacer(),
                _RateMenu(rate: view.rate, onSelected: actions.setRate),
                if (onEpisodes != null)
                  _IconBtn(
                    icon: Icons.format_list_numbered,
                    tooltip: l.watchEpisodes,
                    onPressed: onEpisodes,
                  ),
                if (view.audio.length > 1)
                  _TrackMenu(
                    icon: Icons.audiotrack,
                    tooltip: l.watchAudioTracks,
                    options: view.audio,
                    onSelected: actions.selectAudio,
                  ),
                if (view.subtitles.length > 1)
                  _TrackMenu(
                    icon: Icons.subtitles_outlined,
                    tooltip: l.watchSubtitleTracks,
                    options: view.subtitles,
                    onSelected: actions.selectSubtitle,
                  ),
                _IconBtn(
                  icon: view.fullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  tooltip: '',
                  onPressed: actions.toggleFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _thin(Widget slider) => SliderTheme(
  data: const SliderThemeData(
    trackHeight: 4,
    activeTrackColor: _kAccent,
    inactiveTrackColor: Colors.white30,
    secondaryActiveTrackColor: Colors.white54,
    thumbColor: _kAccent,
    overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
  ),
  child: slider,
);

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.view, required this.onSeek});

  final PlayerView view;
  final void Function(Duration position) onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final double max = widget.view.duration.inMilliseconds
        .clamp(1, 1 << 40)
        .toDouble();
    final double value =
        (_drag ?? widget.view.position.inMilliseconds.toDouble())
            .clamp(0, max)
            .toDouble();
    final double buffered = widget.view.buffered.inMilliseconds
        .clamp(0, max.toInt())
        .toDouble();
    return _thin(
      Slider(
        value: value,
        max: max,
        secondaryTrackValue: buffered > value ? buffered : null,
        onChanged: (double v) => setState(() => _drag = v),
        onChangeEnd: (double v) {
          widget.onSeek(Duration(milliseconds: v.round()));
          setState(() => _drag = null);
        },
      ),
    );
  }
}

class _RateMenu extends StatelessWidget {
  const _RateMenu({required this.rate, required this.onSelected});

  final double rate;
  final void Function(double rate) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: '',
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<double>>[
        for (final double r in kPlaybackRates)
          CheckedPopupMenuItem<double>(
            value: r,
            checked: r == rate,
            child: Text('${_rateLabel(r)}x'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '${_rateLabel(rate)}x',
          style: const TextStyle(
            color: Colors.white,
            fontSize: _kTimeSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _rateLabel(double r) => r == r.roundToDouble() ? '${r.round()}' : '$r';

class _TrackMenu extends StatelessWidget {
  const _TrackMenu({
    required this.icon,
    required this.tooltip,
    required this.options,
    required this.onSelected,
  });

  final IconData icon;
  final String tooltip;
  final List<TrackOption> options;
  final void Function(String id) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.white, size: _kIconSize),
      onSelected: onSelected,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        for (final TrackOption o in options)
          CheckedPopupMenuItem<String>(
            value: o.id,
            checked: o.selected,
            child: Text(o.label),
          ),
      ],
    );
  }
}

const double _kPanelWidth = 380;
const double _kEpisodeExtent = 72;

class _EpisodePanel extends StatefulWidget {
  const _EpisodePanel({
    required this.episodes,
    required this.onSelect,
    required this.onClose,
  });

  final List<EpisodeOption> episodes;
  final void Function(int index) onSelect;
  final VoidCallback onClose;

  @override
  State<_EpisodePanel> createState() => _EpisodePanelState();
}

class _EpisodePanelState extends State<_EpisodePanel> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset:
        (widget.episodes.indexWhere((EpisodeOption e) => e.current) - 2).clamp(
          0,
          widget.episodes.length,
        ) *
        _kEpisodeExtent,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    return SizedBox(
      width: _kPanelWidth,
      child: Material(
        color: const Color(0xE6101418),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l.watchEpisodes,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: _kTitleSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _IconBtn(
                    icon: Icons.close,
                    tooltip: '',
                    size: 26,
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                itemExtent: _kEpisodeExtent,
                itemCount: widget.episodes.length,
                itemBuilder: (BuildContext context, int i) => _EpisodeRow(
                  key: ValueKey<int>(i),
                  episode: widget.episodes[i],
                  onTap: () => widget.onSelect(i),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.onTap, super.key});

  final EpisodeOption episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final EpisodeOption e = episode;
    final bool partial = !e.watched && e.fraction > 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: e.current ? const Color(0x3360CDFF) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 32,
              child: Icon(
                e.current
                    ? Icons.play_arrow
                    : e.watched
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: e.current
                    ? _kAccent
                    : e.watched
                    ? Colors.greenAccent
                    : Colors.white38,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: e.watched && !e.current
                          ? Colors.white54
                          : Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  if (partial) ...<Widget>[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: e.fraction,
                      minHeight: 3,
                      color: _kAccent,
                      backgroundColor: Colors.white24,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
