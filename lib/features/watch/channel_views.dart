import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/providers/settings_provider.dart';
import 'catalog_shelves.dart';

const String kChannelViewsPref = 'watch_channel_views';

class ChannelStat {
  const ChannelStat({required this.count, required this.last});

  factory ChannelStat.fromJson(Map<String, dynamic> json) => ChannelStat(
    count: (json['n'] as num?)?.toInt() ?? 0,
    last: DateTime.fromMillisecondsSinceEpoch(
      (json['t'] as num?)?.toInt() ?? 0,
    ),
  );

  final int count;
  final DateTime last;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'n': count,
    't': last.millisecondsSinceEpoch,
  };
}

/// Names differ in case and spacing between playlist refreshes.
String channelKey(String name) => name.trim().toLowerCase();

/// Most watched first, then most recently watched; unwatched channels keep the
/// playlist order, so the list never reshuffles for no reason.
List<CatalogItem> sortByViews(
  List<CatalogItem> items,
  Map<String, ChannelStat> stats,
) {
  final List<MapEntry<int, CatalogItem>> indexed = <MapEntry<int, CatalogItem>>[
    for (int i = 0; i < items.length; i++)
      MapEntry<int, CatalogItem>(i, items[i]),
  ];
  indexed.sort((MapEntry<int, CatalogItem> a, MapEntry<int, CatalogItem> b) {
    final ChannelStat? sa = stats[channelKey(a.value.title)];
    final ChannelStat? sb = stats[channelKey(b.value.title)];
    final int byCount = (sb?.count ?? 0).compareTo(sa?.count ?? 0);
    if (byCount != 0) return byCount;
    if (sa != null && sb != null) {
      final int byLast = sb.last.compareTo(sa.last);
      if (byLast != 0) return byLast;
    }
    return a.key.compareTo(b.key);
  });
  return <CatalogItem>[
    for (final MapEntry<int, CatalogItem> e in indexed) e.value,
  ];
}

class ChannelViewsNotifier extends Notifier<Map<String, ChannelStat>> {
  static final Logger _log = Logger('ChannelViews');

  late SharedPreferences _prefs;

  @override
  Map<String, ChannelStat> build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    final String? raw = _prefs.getString(kChannelViewsPref);
    if (raw == null || raw.isEmpty) return const <String, ChannelStat>{};
    try {
      final Object? json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const <String, ChannelStat>{};
      return <String, ChannelStat>{
        for (final MapEntry<String, dynamic> e in json.entries)
          if (e.value is Map<String, dynamic>)
            e.key: ChannelStat.fromJson(e.value as Map<String, dynamic>),
      };
    } on FormatException catch (e) {
      _log.warning('channel stats are corrupt, starting empty: $e');
      return const <String, ChannelStat>{};
    }
  }

  void record(String name, {DateTime? at}) {
    final String key = channelKey(name);
    if (key.isEmpty) return;
    final ChannelStat? old = state[key];
    state = <String, ChannelStat>{
      ...state,
      key: ChannelStat(
        count: (old?.count ?? 0) + 1,
        last: at ?? DateTime.now(),
      ),
    };
    _prefs.setString(
      kChannelViewsPref,
      jsonEncode(<String, dynamic>{
        for (final MapEntry<String, ChannelStat> e in state.entries)
          e.key: e.value.toJson(),
      }),
    );
  }
}

final NotifierProvider<ChannelViewsNotifier, Map<String, ChannelStat>>
channelViewsProvider =
    NotifierProvider<ChannelViewsNotifier, Map<String, ChannelStat>>(
      ChannelViewsNotifier.new,
    );
