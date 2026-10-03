import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonkatsu_box/core/api/jacred_api.dart';
import 'package:tonkatsu_box/features/settings/providers/watch_settings_provider.dart';
import 'package:tonkatsu_box/features/watch/providers/watch_providers.dart';
import 'package:tonkatsu_box/features/watch/screens/watch_screen.dart';
import 'package:tonkatsu_box/features/watch/watch_query.dart';

import '../../helpers/test_helpers.dart';

class _ConfiguredSettings extends WatchSettingsNotifier {
  @override
  WatchSettingsState build() => const WatchSettingsState(
    jacRedUrl: 'http://jacred.test',
    torrServerUrl: 'http://torrserver.test',
  );
}

JacRedTorrent torrent(String title) => JacRedTorrent(
  title: title,
  magnet: 'magnet:?xt=urn:btih:${title.hashCode}',
  sizeBytes: 1 << 30,
  seeders: 5,
  peers: 1,
);

void main() {
  const WatchQuery serial = (
    title: 'Show',
    originalTitle: null,
    year: null,
    isSerial: true,
  );

  Future<void> pumpScreen(
    WidgetTester tester,
    WatchQuery query,
    List<JacRedTorrent> results,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpApp(
      WatchScreen(query: query),
      overrides: <Override>[
        watchSettingsProvider.overrideWith(_ConfiguredSettings.new),
        watchResultsProvider.overrideWith(
          (Ref ref, WatchQuery q) async => results,
        ),
      ],
    );
  }

  final List<JacRedTorrent> releases = <JacRedTorrent>[
    torrent('Show S01 1080p'),
    torrent('Show S02 1080p'),
    torrent('Show Сезоны 1-3 720p'),
    torrent('Show complete collection'),
  ];

  testWidgets('a series offers a chip per season found in the releases', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester, serial, releases);

    expect(find.widgetWithText(ChoiceChip, 'All seasons'), findsOneWidget);
    for (final String s in <String>['Season 1', 'Season 2', 'Season 3']) {
      expect(find.widgetWithText(ChoiceChip, s), findsOneWidget);
    }
    expect(find.text('Show complete collection'), findsOneWidget);
  });

  testWidgets('choosing a season keeps only the releases that cover it', (
    WidgetTester tester,
  ) async {
    await pumpScreen(tester, serial, releases);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Season 3'));
    await tester.pumpAndSettle();
    expect(find.text('Show Сезоны 1-3 720p'), findsOneWidget);
    expect(find.text('Show S01 1080p'), findsNothing);
    expect(find.text('Show complete collection'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Season 1'));
    await tester.pumpAndSettle();
    expect(find.text('Show S01 1080p'), findsOneWidget);
    expect(find.text('Show Сезоны 1-3 720p'), findsOneWidget);
    expect(find.text('Show S02 1080p'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All seasons'));
    await tester.pumpAndSettle();
    expect(find.text('Show complete collection'), findsOneWidget);
  });

  testWidgets('a single season gives no chips', (WidgetTester tester) async {
    await pumpScreen(tester, serial, <JacRedTorrent>[
      torrent('Show S02 1080p'),
      torrent('Show S02 720p'),
    ]);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('a film never gets season chips', (WidgetTester tester) async {
    await pumpScreen(tester, (
      title: 'Film',
      originalTitle: null,
      year: 2020,
      isSerial: false,
    ), releases);
    expect(find.byType(ChoiceChip), findsNothing);
  });
}
