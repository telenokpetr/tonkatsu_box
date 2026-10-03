import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonkatsu_box/core/api/torrserver_api.dart';
import 'package:tonkatsu_box/features/watch/screens/episode_picker.dart';
import 'package:tonkatsu_box/features/watch/watch_episodes.dart';
import 'package:tonkatsu_box/features/watch/watch_progress.dart';

import '../../helpers/test_helpers.dart';

const String _hash = 'abc';

List<EpisodeEntry> season(
  int s,
  int count, {
  int firstId = 1,
}) => orderEpisodes(<TorrServerFile>[
  for (int e = 1; e <= count; e++)
    TorrServerFile(
      id: firstId + e - 1,
      path:
          'Show.S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}.mkv',
      length: 1 << 20,
    ),
]);

void main() {
  Future<ProviderContainer> pumpPicker(
    WidgetTester tester,
    List<EpisodeEntry> entries, {
    void Function(WatchProgressNotifier notifier)? seed,
    void Function(TorrServerFile?)? onResult,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpApp(
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () async {
            final TorrServerFile? file = await showEpisodePicker(
              context,
              hash: _hash,
              title: 'Show',
              entries: entries,
            );
            onResult?.call(file);
          },
          child: const Text('open'),
        ),
      ),
    );
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.text('open')),
    );
    seed?.call(container.read(watchProgressProvider.notifier));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('lists episodes and returns the tapped one', (
    WidgetTester tester,
  ) async {
    TorrServerFile? picked;
    await pumpPicker(
      tester,
      season(1, 3),
      onResult: (TorrServerFile? f) => picked = f,
    );

    expect(find.text('Episode 1'), findsOneWidget);
    expect(find.text('Episode 3'), findsOneWidget);
    expect(find.textContaining('Continue'), findsNothing);

    await tester.tap(find.text('Episode 2'));
    await tester.pumpAndSettle();
    expect(picked?.id, 2);
  });

  testWidgets('offers to continue an unfinished episode', (
    WidgetTester tester,
  ) async {
    TorrServerFile? picked;
    await pumpPicker(
      tester,
      season(1, 4),
      seed: (WatchProgressNotifier n) {
        n.setWatched(
          progressKey(_hash, 'Show.S01E01.mkv'),
          watched: true,
          at: DateTime(2026),
        );
        n.record(
          progressKey(_hash, 'Show.S01E02.mkv'),
          const Duration(minutes: 12, seconds: 34),
          const Duration(minutes: 45),
          at: DateTime(2026, 2),
        );
      },
      onResult: (TorrServerFile? f) => picked = f,
    );

    expect(find.text('Continue: Episode 2'), findsOneWidget);
    expect(find.textContaining('12:34'), findsWidgets);

    await tester.tap(find.text('Continue: Episode 2'));
    await tester.pumpAndSettle();
    expect(picked?.id, 2);
  });

  testWidgets('continue moves to the next episode after a finished one', (
    WidgetTester tester,
  ) async {
    await pumpPicker(
      tester,
      season(1, 3),
      seed: (WatchProgressNotifier n) => n.record(
        progressKey(_hash, 'Show.S01E01.mkv'),
        const Duration(minutes: 39),
        const Duration(minutes: 40),
      ),
    );
    expect(find.text('Continue: Episode 2'), findsOneWidget);
  });

  testWidgets('seasons are chips and the last watched one opens first', (
    WidgetTester tester,
  ) async {
    await pumpPicker(
      tester,
      <EpisodeEntry>[...season(1, 2), ...season(2, 2, firstId: 3)],
      seed: (WatchProgressNotifier n) => n.record(
        progressKey(_hash, 'Show.S02E01.mkv'),
        const Duration(minutes: 10),
        const Duration(minutes: 40),
      ),
    );

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    expect(find.text('Episode 1'), findsWidgets);
    final ChoiceChip second = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Season 2'),
    );
    expect(second.selected, isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Season 1'));
    await tester.pumpAndSettle();
    final ChoiceChip first = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Season 1'),
    );
    expect(first.selected, isTrue);
  });

  testWidgets('marking an episode watched shows the check', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpPicker(tester, season(1, 2));
    expect(find.byIcon(Icons.check_circle), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as watched'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      container
          .read(watchProgressProvider)[progressKey(_hash, 'Show.S01E01.mkv')]
          ?.watched,
      isTrue,
    );
  });

  testWidgets('from the beginning forgets the saved position', (
    WidgetTester tester,
  ) async {
    TorrServerFile? picked;
    final ProviderContainer container = await pumpPicker(
      tester,
      season(1, 2),
      seed: (WatchProgressNotifier n) => n.record(
        progressKey(_hash, 'Show.S01E01.mkv'),
        const Duration(minutes: 10),
        const Duration(minutes: 40),
      ),
      onResult: (TorrServerFile? f) => picked = f,
    );

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('From the beginning'));
    await tester.pumpAndSettle();

    expect(picked?.id, 1);
    expect(
      container
          .read(watchProgressProvider)
          .containsKey(progressKey(_hash, 'Show.S01E01.mkv')),
      isFalse,
    );
  });
}
