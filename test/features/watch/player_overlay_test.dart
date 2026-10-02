import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonkatsu_box/features/watch/player/player_overlay.dart';
import 'package:tonkatsu_box/features/watch/player/player_state.dart';

import '../../helpers/test_helpers.dart';

class _Calls {
  final List<String> log = <String>[];
  Duration? seekedTo;
  double? volume;
  double? rate;
  String? audio;
  String? subtitle;

  PlayerActions get actions => PlayerActions(
    togglePlay: () => log.add('togglePlay'),
    seek: (Duration d) {
      log.add('seek');
      seekedTo = d;
    },
    setVolume: (double v) {
      log.add('volume');
      volume = v;
    },
    setRate: (double r) {
      log.add('rate');
      rate = r;
    },
    selectAudio: (String id) {
      log.add('audio');
      audio = id;
    },
    selectSubtitle: (String id) {
      log.add('subtitle');
      subtitle = id;
    },
    previous: () => log.add('previous'),
    next: () => log.add('next'),
    toggleFullscreen: () => log.add('fullscreen'),
    exitFullscreen: () => log.add('exitFullscreen'),
    back: () => log.add('back'),
    copyLink: () => log.add('copyLink'),
  );
}

PlayerView view({
  bool playing = true,
  bool fullscreen = false,
  bool hasPrevious = true,
  bool hasNext = true,
  double volume = 80,
  Duration position = const Duration(minutes: 5),
  List<TrackOption> audio = const <TrackOption>[],
  List<TrackOption> subtitles = const <TrackOption>[],
}) {
  return PlayerView(
    title: 'Movie.mkv',
    position: position,
    duration: const Duration(minutes: 90),
    playing: playing,
    volume: volume,
    hasPrevious: hasPrevious,
    hasNext: hasNext,
    fullscreen: fullscreen,
    audio: audio,
    subtitles: subtitles,
  );
}

const List<TrackOption> twoAudio = <TrackOption>[
  TrackOption(id: '1', label: 'Dub', selected: true),
  TrackOption(id: '2', label: 'Original', selected: false),
];

void main() {
  Future<_Calls> pump(
    WidgetTester tester,
    PlayerView v, {
    Duration hideAfter = const Duration(seconds: 3),
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final _Calls calls = _Calls();
    await tester.pumpApp(
      Scaffold(
        backgroundColor: Colors.black,
        body: PlayerOverlay(
          view: v,
          actions: calls.actions,
          hideAfter: hideAfter,
        ),
      ),
    );
    return calls;
  }

  group('nextTrack', () {
    test('wraps around after the selected option', () {
      expect(nextTrack(twoAudio)?.id, '2');
      expect(
        nextTrack(const <TrackOption>[
          TrackOption(id: '1', label: 'a', selected: false),
          TrackOption(id: '2', label: 'b', selected: true),
        ])?.id,
        '1',
      );
    });

    test('nothing to cycle with fewer than two options', () {
      expect(nextTrack(const <TrackOption>[]), isNull);
      expect(nextTrack(twoAudio.take(1).toList()), isNull);
    });
  });

  group('PlayerOverlay', () {
    testWidgets('shows the title and the position over the duration', (
      WidgetTester tester,
    ) async {
      await pump(tester, view());

      expect(tester.takeException(), isNull);
      expect(find.text('Movie.mkv'), findsOneWidget);
      expect(find.text('5:00 / 1:30:00'), findsOneWidget);
    });

    testWidgets('the play button and a tap on the picture toggle playback', (
      WidgetTester tester,
    ) async {
      final _Calls calls = await pump(tester, view());

      await tester.tap(find.byIcon(Icons.pause));
      await tester.tapAt(const Offset(640, 300));
      await tester.pump(const Duration(milliseconds: 400));

      expect(calls.log, <String>['togglePlay', 'togglePlay']);
    });

    testWidgets('space and K toggle, arrows seek, ctrl takes the big step', (
      WidgetTester tester,
    ) async {
      final _Calls calls = await pump(tester, view());

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(calls.log.last, 'togglePlay');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(calls.seekedTo, const Duration(minutes: 5, seconds: 10));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(calls.seekedTo, const Duration(minutes: 4, seconds: 50));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(calls.seekedTo, const Duration(minutes: 6));
    });

    testWidgets('a seek never goes below zero or past the end', (
      WidgetTester tester,
    ) async {
      final _Calls calls = await pump(
        tester,
        view(position: const Duration(seconds: 4)),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);

      expect(calls.seekedTo, Duration.zero);
    });

    testWidgets('up and down change the volume in steps of five', (
      WidgetTester tester,
    ) async {
      final _Calls calls = await pump(tester, view(volume: 80));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(calls.volume, 85);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(calls.volume, 75);
    });

    testWidgets('the volume stays within 0 and 100', (
      WidgetTester tester,
    ) async {
      final _Calls calls = await pump(tester, view(volume: 98));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);

      expect(calls.volume, 100);
    });

    testWidgets('M mutes, and unmutes back to the previous level', (
      WidgetTester tester,
    ) async {
      final _Calls calls = await pump(tester, view(volume: 60));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(calls.volume, 0);

      await tester.pumpWidget(const SizedBox());
      final _Calls muted = await pump(tester, view(volume: 0));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(muted.volume, 100);
    });

    testWidgets('F and F11 toggle fullscreen, double tap too', (
      WidgetTester tester,
    ) async {
      final _Calls calls = await pump(tester, view());

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.tapAt(const Offset(640, 300));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(const Offset(640, 300));
      await tester.pump(const Duration(milliseconds: 400));

      expect(calls.log.where((String e) => e == 'fullscreen'), hasLength(3));
    });

    testWidgets('escape leaves fullscreen first, then goes back', (
      WidgetTester tester,
    ) async {
      final _Calls inFullscreen = await pump(tester, view(fullscreen: true));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(inFullscreen.log.last, 'exitFullscreen');

      await tester.pumpWidget(const SizedBox());
      final _Calls windowed = await pump(tester, view());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(windowed.log.last, 'back');
    });

    testWidgets('N and P move through the playlist only when there is a step', (
      WidgetTester tester,
    ) async {
      final _Calls both = await pump(tester, view());
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      expect(both.log, containsAllInOrder(<String>['next', 'previous']));

      await tester.pumpWidget(const SizedBox());
      final _Calls none = await pump(
        tester,
        view(hasNext: false, hasPrevious: false),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      expect(
        none.log.where((String e) => e == 'next' || e == 'previous'),
        isEmpty,
      );
    });

    testWidgets('A cycles the audio track and S the subtitles', (
      WidgetTester tester,
    ) async {
      final _Calls calls = await pump(
        tester,
        view(
          audio: twoAudio,
          subtitles: const <TrackOption>[
            TrackOption(id: 'no', label: 'Off', selected: true),
            TrackOption(id: '7', label: 'Russian', selected: false),
          ],
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);

      expect(calls.audio, '2');
      expect(calls.subtitle, '7');
    });

    testWidgets('the audio menu appears only with two or more tracks', (
      WidgetTester tester,
    ) async {
      await pump(tester, view());
      expect(find.byIcon(Icons.audiotrack), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await pump(tester, view(audio: twoAudio));
      expect(find.byIcon(Icons.audiotrack), findsOneWidget);
    });

    testWidgets('picking an audio track from the menu selects it', (
      WidgetTester tester,
    ) async {
      final _Calls calls = await pump(tester, view(audio: twoAudio));

      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(calls.audio, '2');
    });

    testWidgets('the speed menu sets the rate', (WidgetTester tester) async {
      final _Calls calls = await pump(tester, view());

      await tester.tap(find.text('1x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5x'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(calls.rate, 1.5);
    });

    testWidgets('previous and next buttons are disabled at the ends', (
      WidgetTester tester,
    ) async {
      final _Calls calls = await pump(
        tester,
        view(hasPrevious: false, hasNext: false),
      );

      await tester.tap(find.byIcon(Icons.skip_previous));
      await tester.tap(find.byIcon(Icons.skip_next));

      expect(calls.log, isEmpty);
    });

    testWidgets('the panel hides while playing and the mouse reveals it', (
      WidgetTester tester,
    ) async {
      await pump(tester, view(), hideAfter: const Duration(seconds: 1));
      AnimatedOpacity opacity() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity().opacity, 1);

      await tester.pump(const Duration(seconds: 2));
      expect(opacity().opacity, 0);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(300, 300));
      await tester.pump();
      expect(opacity().opacity, 1);
    });

    testWidgets('the panel stays up while paused', (WidgetTester tester) async {
      await pump(
        tester,
        view(playing: false),
        hideAfter: const Duration(seconds: 1),
      );

      await tester.pump(const Duration(seconds: 5));

      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
    });

    testWidgets('the back button goes back', (WidgetTester tester) async {
      final _Calls calls = await pump(tester, view());

      await tester.tap(find.byIcon(Icons.arrow_back));

      expect(calls.log.last, 'back');
    });
  });
}
