import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/providers/settings_provider.dart';

const String kWatchProgressPref = 'watch_progress';
const double kWatchedFraction = 0.92;
const Duration kWatchedTail = Duration(seconds: 90);
const Duration kMinResume = Duration(seconds: 15);
const int kMaxProgressEntries = 600;

/// Stable per-file key; the torrent hash survives re-adding the same release.
String progressKey(String hash, String path) => '$hash/$path';

class WatchProgress {
  const WatchProgress({
    required this.position,
    required this.duration,
    required this.updated,
    this.watched = false,
  });

  factory WatchProgress.fromJson(Map<String, dynamic> json) {
    return WatchProgress(
      position: Duration(seconds: (json['p'] as num?)?.toInt() ?? 0),
      duration: Duration(seconds: (json['d'] as num?)?.toInt() ?? 0),
      updated: DateTime.fromMillisecondsSinceEpoch(
        (json['u'] as num?)?.toInt() ?? 0,
      ),
      watched: json['w'] == true,
    );
  }

  final Duration position;
  final Duration duration;
  final DateTime updated;
  final bool watched;

  /// 0-1 share of the file already seen.
  double get fraction {
    if (watched) return 1;
    if (duration <= Duration.zero) return 0;
    return (position.inSeconds / duration.inSeconds).clamp(0, 1).toDouble();
  }

  /// Where to carry on; null for a finished or barely started file.
  Duration? get resumeAt => watched || position < kMinResume ? null : position;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'p': position.inSeconds,
    'd': duration.inSeconds,
    'u': updated.millisecondsSinceEpoch,
    if (watched) 'w': true,
  };
}

/// The key whose progress was touched last, or null when none of [keys] has any.
String? lastWatchedKey(
  Map<String, WatchProgress> progress,
  Iterable<String> keys,
) {
  String? best;
  DateTime? bestTime;
  for (final String key in keys) {
    final WatchProgress? entry = progress[key];
    if (entry == null) continue;
    if (bestTime == null || entry.updated.isAfter(bestTime)) {
      best = key;
      bestTime = entry.updated;
    }
  }
  return best;
}

class WatchProgressNotifier extends Notifier<Map<String, WatchProgress>> {
  static final Logger _log = Logger('WatchProgress');

  late SharedPreferences _prefs;

  @override
  Map<String, WatchProgress> build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return _load(_prefs.getString(kWatchProgressPref));
  }

  Map<String, WatchProgress> _load(String? raw) {
    if (raw == null || raw.isEmpty) return const <String, WatchProgress>{};
    try {
      final Object? json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return const <String, WatchProgress>{};
      }
      return <String, WatchProgress>{
        for (final MapEntry<String, dynamic> e in json.entries)
          if (e.value is Map<String, dynamic>)
            e.key: WatchProgress.fromJson(e.value as Map<String, dynamic>),
      };
    } on FormatException catch (e) {
      _log.warning('progress store is corrupt, starting empty: $e');
      return const <String, WatchProgress>{};
    }
  }

  void _save(Map<String, WatchProgress> next) {
    Map<String, WatchProgress> kept = next;
    if (next.length > kMaxProgressEntries) {
      final List<MapEntry<String, WatchProgress>> sorted = next.entries.toList()
        ..sort(
          (
            MapEntry<String, WatchProgress> a,
            MapEntry<String, WatchProgress> b,
          ) => b.value.updated.compareTo(a.value.updated),
        );
      kept = Map<String, WatchProgress>.fromEntries(
        sorted.take(kMaxProgressEntries),
      );
    }
    state = kept;
    _prefs.setString(
      kWatchProgressPref,
      jsonEncode(<String, dynamic>{
        for (final MapEntry<String, WatchProgress> e in kept.entries)
          e.key: e.value.toJson(),
      }),
    );
  }

  /// Stores where playback stopped; a file seen to its end counts as watched.
  void record(
    String key,
    Duration position,
    Duration duration, {
    DateTime? at,
  }) {
    if (duration <= Duration.zero) return;
    final bool done =
        position.inSeconds >= duration.inSeconds * kWatchedFraction ||
        duration - position <= kWatchedTail;
    _save(<String, WatchProgress>{
      ...state,
      key: WatchProgress(
        position: done ? Duration.zero : position,
        duration: duration,
        updated: at ?? DateTime.now(),
        watched: done,
      ),
    });
  }

  void setWatched(String key, {required bool watched, DateTime? at}) {
    final WatchProgress? old = state[key];
    _save(<String, WatchProgress>{
      ...state,
      key: WatchProgress(
        position: Duration.zero,
        duration: old?.duration ?? Duration.zero,
        updated: at ?? DateTime.now(),
        watched: watched,
      ),
    });
  }

  void reset(String key) {
    if (!state.containsKey(key)) return;
    _save(<String, WatchProgress>{...state}..remove(key));
  }
}

final NotifierProvider<WatchProgressNotifier, Map<String, WatchProgress>>
watchProgressProvider =
    NotifierProvider<WatchProgressNotifier, Map<String, WatchProgress>>(
      WatchProgressNotifier.new,
    );
