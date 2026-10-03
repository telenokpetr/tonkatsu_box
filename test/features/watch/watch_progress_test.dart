import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tonkatsu_box/features/settings/providers/settings_provider.dart';
import 'package:tonkatsu_box/features/watch/watch_episodes.dart';
import 'package:tonkatsu_box/features/watch/watch_progress.dart';

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

  const Duration hour = Duration(minutes: 60);

  group('WatchProgress', () {
    test('fraction and resume point', () {
      final WatchProgress p = WatchProgress(
        position: const Duration(minutes: 15),
        duration: hour,
        updated: DateTime(2026),
      );
      expect(p.fraction, 0.25);
      expect(p.resumeAt, const Duration(minutes: 15));
    });

    test('a barely started file does not resume', () {
      final WatchProgress p = WatchProgress(
        position: const Duration(seconds: 5),
        duration: hour,
        updated: DateTime(2026),
      );
      expect(p.resumeAt, isNull);
    });

    test('a watched file is full and never resumes', () {
      final WatchProgress p = WatchProgress(
        position: Duration.zero,
        duration: hour,
        updated: DateTime(2026),
        watched: true,
      );
      expect(p.fraction, 1);
      expect(p.resumeAt, isNull);
    });

    test('unknown duration gives zero fraction', () {
      final WatchProgress p = WatchProgress(
        position: const Duration(minutes: 3),
        duration: Duration.zero,
        updated: DateTime(2026),
      );
      expect(p.fraction, 0);
    });

    test('survives a JSON round trip', () {
      final WatchProgress p = WatchProgress(
        position: const Duration(minutes: 7),
        duration: hour,
        updated: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        watched: true,
      );
      final WatchProgress back = WatchProgress.fromJson(p.toJson());
      expect(back.position, p.position);
      expect(back.duration, p.duration);
      expect(back.updated, p.updated);
      expect(back.watched, isTrue);
    });
  });

  group('WatchProgressNotifier', () {
    test(
      'records where playback stopped and keeps it in preferences',
      () async {
        final ProviderContainer c = await container();
        c
            .read(watchProgressProvider.notifier)
            .record('h/a.mkv', const Duration(minutes: 20), hour);

        final WatchProgress? saved = c.read(watchProgressProvider)['h/a.mkv'];
        expect(saved?.position, const Duration(minutes: 20));
        expect(saved?.watched, isFalse);

        final SharedPreferences prefs = c.read(sharedPreferencesProvider);
        expect(prefs.getString(kWatchProgressPref), contains('h/a.mkv'));
      },
    );

    test('reaching the end marks the file watched', () async {
      final ProviderContainer c = await container();
      final WatchProgressNotifier n = c.read(watchProgressProvider.notifier);
      n.record('k1', const Duration(minutes: 57), hour);
      n.record('k2', const Duration(minutes: 59), hour);

      expect(c.read(watchProgressProvider)['k1']?.watched, isTrue);
      expect(c.read(watchProgressProvider)['k2']?.watched, isTrue);
      expect(c.read(watchProgressProvider)['k1']?.resumeAt, isNull);
    });

    test('ignores a report without a duration', () async {
      final ProviderContainer c = await container();
      c
          .read(watchProgressProvider.notifier)
          .record('k', const Duration(minutes: 1), Duration.zero);
      expect(c.read(watchProgressProvider), isEmpty);
    });

    test('marks watched, unwatched and resets', () async {
      final ProviderContainer c = await container();
      final WatchProgressNotifier n = c.read(watchProgressProvider.notifier);
      n.setWatched('k', watched: true);
      expect(c.read(watchProgressProvider)['k']?.watched, isTrue);
      n.setWatched('k', watched: false);
      expect(c.read(watchProgressProvider)['k']?.watched, isFalse);
      n.reset('k');
      expect(c.read(watchProgressProvider), isEmpty);
      n.reset('missing');
    });

    test('loads what an earlier run saved', () async {
      final ProviderContainer first = await container();
      first
          .read(watchProgressProvider.notifier)
          .record('k', const Duration(minutes: 9), hour);
      final String raw = first
          .read(sharedPreferencesProvider)
          .getString(kWatchProgressPref)!;

      final ProviderContainer second = await container(<String, Object>{
        kWatchProgressPref: raw,
      });
      expect(
        second.read(watchProgressProvider)['k']?.position,
        const Duration(minutes: 9),
      );
    });

    test('a corrupt store starts empty', () async {
      final ProviderContainer c = await container(<String, Object>{
        kWatchProgressPref: '{not json',
      });
      expect(c.read(watchProgressProvider), isEmpty);
    });

    test('a store of the wrong shape starts empty', () async {
      final ProviderContainer c = await container(<String, Object>{
        kWatchProgressPref: '[1,2]',
      });
      expect(c.read(watchProgressProvider), isEmpty);
    });

    test('keeps only the most recent entries', () async {
      final ProviderContainer c = await container();
      final WatchProgressNotifier n = c.read(watchProgressProvider.notifier);
      for (int i = 0; i < kMaxProgressEntries + 5; i++) {
        n.record('k$i', const Duration(minutes: 5), hour);
      }
      expect(c.read(watchProgressProvider), hasLength(kMaxProgressEntries));
      expect(c.read(watchProgressProvider).containsKey('k0'), isFalse);
    });
  });

  group('lastWatchedKey', () {
    test('picks the most recently touched of the given keys', () {
      final Map<String, WatchProgress> progress = <String, WatchProgress>{
        'a': WatchProgress(
          position: Duration.zero,
          duration: hour,
          updated: DateTime(2026, 1, 1),
        ),
        'b': WatchProgress(
          position: Duration.zero,
          duration: hour,
          updated: DateTime(2026, 3, 1),
        ),
        'other': WatchProgress(
          position: Duration.zero,
          duration: hour,
          updated: DateTime(2026, 9, 1),
        ),
      };
      expect(lastWatchedKey(progress, <String>['a', 'b', 'c']), 'b');
    });

    test('null when none has progress', () {
      expect(lastWatchedKey(<String, WatchProgress>{}, <String>['a']), isNull);
    });
  });

  group('continueIndex', () {
    WatchProgress entry(DateTime at, {bool watched = false}) => WatchProgress(
      position: watched ? Duration.zero : const Duration(minutes: 5),
      duration: hour,
      updated: at,
      watched: watched,
    );

    test('nothing watched yet', () {
      expect(
        continueIndex(<String>['a', 'b'], <String, WatchProgress>{}),
        isNull,
      );
    });

    test('an unfinished file continues itself', () {
      expect(
        continueIndex(
          <String>['a', 'b', 'c'],
          <String, WatchProgress>{
            'a': entry(DateTime(2026, 1, 1), watched: true),
            'b': entry(DateTime(2026, 1, 2)),
          },
        ),
        1,
      );
    });

    test('a finished file moves on to the next one', () {
      expect(
        continueIndex(
          <String>['a', 'b', 'c'],
          <String, WatchProgress>{
            'a': entry(DateTime(2026, 1, 1), watched: true),
            'b': entry(DateTime(2026, 1, 2), watched: true),
          },
        ),
        2,
      );
    });

    test('the finished last file leaves nothing to continue', () {
      expect(
        continueIndex(
          <String>['a', 'b'],
          <String, WatchProgress>{
            'b': entry(DateTime(2026, 1, 2), watched: true),
          },
        ),
        isNull,
      );
    });
  });

  test('progressKey joins hash and path', () {
    expect(progressKey('abc', 'S1/e1.mkv'), 'abc/S1/e1.mkv');
  });
}
