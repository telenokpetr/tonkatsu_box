/// One audio or subtitle choice in the player menus.
class TrackOption {
  const TrackOption({
    required this.id,
    required this.label,
    required this.selected,
  });

  final String id;
  final String label;
  final bool selected;
}

/// One row of the episode panel.
class EpisodeOption {
  const EpisodeOption({
    required this.title,
    this.fraction = 0,
    this.watched = false,
    this.current = false,
  });

  final String title;

  /// 0-1 share already seen.
  final double fraction;
  final bool watched;
  final bool current;
}

/// Everything the control panel draws; the libmpv binding fills it in and the
/// panel never touches the player, which keeps it testable without libmpv.
class PlayerView {
  const PlayerView({
    required this.title,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.volume = 100,
    this.rate = 1,
    this.audio = const <TrackOption>[],
    this.subtitles = const <TrackOption>[],
    this.hasPrevious = false,
    this.hasNext = false,
    this.fullscreen = false,
    this.episodes = const <EpisodeOption>[],
  });

  final String title;
  final Duration position;
  final Duration duration;

  /// How far the stream is already loaded, ahead of [position].
  final Duration buffered;
  final bool playing;
  final bool buffering;

  /// 0-100.
  final double volume;
  final double rate;
  final List<TrackOption> audio;

  /// Includes the "off" choice first.
  final List<TrackOption> subtitles;
  final bool hasPrevious;
  final bool hasNext;
  final bool fullscreen;

  /// The playlist as episodes; the panel is offered when there are several.
  final List<EpisodeOption> episodes;
}

class PlayerActions {
  const PlayerActions({
    required this.togglePlay,
    required this.seek,
    required this.setVolume,
    required this.setRate,
    required this.selectAudio,
    required this.selectSubtitle,
    required this.previous,
    required this.next,
    required this.toggleFullscreen,
    required this.exitFullscreen,
    required this.back,
    required this.copyLink,
    this.selectEpisode,
  });

  final void Function() togglePlay;
  final void Function(Duration position) seek;
  final void Function(double volume) setVolume;
  final void Function(double rate) setRate;
  final void Function(String id) selectAudio;
  final void Function(String id) selectSubtitle;
  final void Function() previous;
  final void Function() next;
  final void Function() toggleFullscreen;
  final void Function() exitFullscreen;
  final void Function() back;
  final void Function() copyLink;
  final void Function(int index)? selectEpisode;
}

const List<double> kPlaybackRates = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];

/// The option after the selected one, wrapping around; used by the A and S
/// keys. Null when there is nothing to cycle through.
TrackOption? nextTrack(List<TrackOption> options) {
  if (options.length < 2) return null;
  final int current = options.indexWhere((TrackOption o) => o.selected);
  return options[(current + 1) % options.length];
}
