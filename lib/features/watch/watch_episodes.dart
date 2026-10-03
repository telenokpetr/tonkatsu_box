import '../../core/api/torrserver_api.dart';
import '../../l10n/app_localizations.dart';
import 'watch_progress.dart';
import 'watch_format.dart';

class EpisodeId {
  const EpisodeId({this.season, this.episode});

  final int? season;
  final int? episode;
}

final RegExp _seasonEpisode = RegExp(
  r'(?:^|[^a-z0-9])s(\d{1,2})[\s._-]?e(\d{1,3})(?![0-9])',
  caseSensitive: false,
);
final RegExp _crossForm = RegExp(r'(?:^|[^0-9])(\d{1,2})x(\d{2,3})(?![0-9])');
final RegExp _wordEpisode = RegExp(
  r'(?:серия|серии|эпизод|episode|ep\.?)\s*[#№]?\s*(\d{1,3})(?![0-9])',
  caseSensitive: false,
);
final RegExp _bareNumber = RegExp(
  r'(?:^|[\s\[\(._-])(\d{1,3})(?=[\s\]\)._v-]|$)',
);
final RegExp _seasonFolder = RegExp(
  r'(?:season|сезон|series|s)[\s._-]*(\d{1,2})(?![0-9])',
  caseSensitive: false,
);

/// Season and episode number read from a file path, null parts when the
/// release does not say; the folder name supplies the season for flat names.
EpisodeId parseEpisode(String path) {
  final List<String> parts = path.split('/');
  final String name = parts.last;
  final RegExpMatch? full = _seasonEpisode.firstMatch(name);
  if (full != null) {
    return EpisodeId(
      season: int.parse(full.group(1) ?? '0'),
      episode: int.parse(full.group(2) ?? '0'),
    );
  }
  final RegExpMatch? cross = _crossForm.firstMatch(name);
  if (cross != null) {
    return EpisodeId(
      season: int.parse(cross.group(1) ?? '0'),
      episode: int.parse(cross.group(2) ?? '0'),
    );
  }
  int? season;
  for (final String folder in parts.take(parts.length - 1).toList().reversed) {
    final RegExpMatch? m = _seasonFolder.firstMatch(folder);
    if (m != null) {
      season = int.parse(m.group(1) ?? '0');
      break;
    }
  }
  final String bare = name.replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '');
  final RegExpMatch? word = _wordEpisode.firstMatch(bare);
  if (word != null) {
    return EpisodeId(season: season, episode: int.parse(word.group(1) ?? '0'));
  }
  final RegExpMatch? number = _bareNumber.firstMatch(bare);
  if (number != null) {
    return EpisodeId(
      season: season,
      episode: int.parse(number.group(1) ?? '0'),
    );
  }
  return EpisodeId(season: season);
}

/// `S01E05`, `E5` or null when the file carries no number.
String? episodeCode(EpisodeId id) {
  final int? episode = id.episode;
  if (episode == null) return null;
  final int? season = id.season;
  final String e = episode.toString().padLeft(2, '0');
  return season == null ? 'E$e' : 'S${season.toString().padLeft(2, '0')}E$e';
}

class EpisodeEntry {
  const EpisodeEntry({required this.file, required this.id});

  final TorrServerFile file;
  final EpisodeId id;
}

/// Files in watching order: by season and episode where known, then by name.
List<EpisodeEntry> orderEpisodes(List<TorrServerFile> files) {
  final List<EpisodeEntry> entries = <EpisodeEntry>[
    for (final TorrServerFile f in files)
      EpisodeEntry(file: f, id: parseEpisode(f.path)),
  ];
  entries.sort((EpisodeEntry a, EpisodeEntry b) {
    final int season = (a.id.season ?? 0).compareTo(b.id.season ?? 0);
    if (season != 0) return season;
    final int? ea = a.id.episode;
    final int? eb = b.id.episode;
    if (ea != null && eb != null && ea != eb) return ea.compareTo(eb);
    return naturalCompare(a.file.path, b.file.path);
  });
  return entries;
}

/// "Season 2 · Episode 5", or the file name when it carries no number.
String episodeLabel(
  S l,
  EpisodeId id,
  String fallback, {
  bool withSeason = false,
}) {
  final int? episode = id.episode;
  if (episode == null) return fallback;
  final int? season = id.season;
  final String ep = l.watchEpisodeNumber(episode);
  return withSeason && season != null ? '${l.watchSeason(season)} · $ep' : ep;
}

/// Where "Continue" should land: the last touched file while it is unfinished,
/// the one after it once it is watched, null when nothing was watched yet.
int? continueIndex(List<String> keys, Map<String, WatchProgress> progress) {
  final String? last = lastWatchedKey(progress, keys);
  if (last == null) return null;
  final int at = keys.indexOf(last);
  if (progress[last]?.watched != true) return at;
  return at + 1 < keys.length ? at + 1 : null;
}
