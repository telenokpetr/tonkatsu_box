import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tonkatsu_box/features/settings/providers/settings_provider.dart';
import 'package:tonkatsu_box/features/watch/catalog_shelves.dart';
import 'package:tonkatsu_box/features/watch/channel_views.dart';

CatalogItem channel(String name) => CatalogItem(
  title: name,
  isSerial: false,
  streamUrl: 'http://s/${name.hashCode}',
);

List<String> names(List<CatalogItem> items) =>
    items.map((CatalogItem c) => c.title).toList();

void main() {
  Future<ProviderContainer> container([
    Map<String, Object> initial = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(initial);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('sortByViews', () {
    final List<CatalogItem> playlist = <CatalogItem>[
      channel('Alpha'),
      channel('Beta'),
      channel('Gamma'),
      channel('Delta'),
    ];

    test('most watched first', () {
      final List<CatalogItem> sorted =
          sortByViews(playlist, <String, ChannelStat>{
            'gamma': ChannelStat(count: 9, last: DateTime(2026)),
            'beta': ChannelStat(count: 3, last: DateTime(2026)),
          });
      expect(names(sorted), <String>['Gamma', 'Beta', 'Alpha', 'Delta']);
    });

    test('equal counts go to the most recently watched', () {
      final List<CatalogItem> sorted =
          sortByViews(playlist, <String, ChannelStat>{
            'alpha': ChannelStat(count: 2, last: DateTime(2026, 1, 1)),
            'delta': ChannelStat(count: 2, last: DateTime(2026, 6, 1)),
          });
      expect(names(sorted).take(2), <String>['Delta', 'Alpha']);
    });

    test('unwatched channels keep the playlist order', () {
      expect(
        names(sortByViews(playlist, const <String, ChannelStat>{})),
        <String>['Alpha', 'Beta', 'Gamma', 'Delta'],
      );
    });

    test('names match regardless of case and spacing', () {
      final List<CatalogItem> sorted = sortByViews(
        playlist,
        <String, ChannelStat>{
          channelKey('  DELTA '): ChannelStat(count: 1, last: DateTime(2026)),
        },
      );
      expect(sorted.first.title, 'Delta');
    });

    test('empty stays empty', () {
      expect(
        sortByViews(<CatalogItem>[], const <String, ChannelStat>{}),
        isEmpty,
      );
    });
  });

  group('ChannelViewsNotifier', () {
    test('counts every start and keeps the last time', () async {
      final ProviderContainer c = await container();
      final ChannelViewsNotifier n = c.read(channelViewsProvider.notifier);
      n.record('Первый', at: DateTime(2026, 1, 1));
      n.record(' первый ', at: DateTime(2026, 2, 1));
      n.record('Второй');

      final Map<String, ChannelStat> stats = c.read(channelViewsProvider);
      expect(stats[channelKey('Первый')]?.count, 2);
      expect(stats[channelKey('Первый')]?.last, DateTime(2026, 2, 1));
      expect(stats[channelKey('Второй')]?.count, 1);
    });

    test('ignores a blank name', () async {
      final ProviderContainer c = await container();
      c.read(channelViewsProvider.notifier).record('   ');
      expect(c.read(channelViewsProvider), isEmpty);
    });

    test('what was counted survives a restart', () async {
      final ProviderContainer first = await container();
      first
          .read(channelViewsProvider.notifier)
          .record('Match', at: DateTime(2026));
      final String raw = first
          .read(sharedPreferencesProvider)
          .getString(kChannelViewsPref)!;

      final ProviderContainer second = await container(<String, Object>{
        kChannelViewsPref: raw,
      });
      expect(second.read(channelViewsProvider)[channelKey('Match')]?.count, 1);
    });

    test('a corrupt or foreign store starts empty', () async {
      final ProviderContainer broken = await container(<String, Object>{
        kChannelViewsPref: '{oops',
      });
      expect(broken.read(channelViewsProvider), isEmpty);

      final ProviderContainer wrong = await container(<String, Object>{
        kChannelViewsPref: '[1]',
      });
      expect(wrong.read(channelViewsProvider), isEmpty);
    });
  });
}
