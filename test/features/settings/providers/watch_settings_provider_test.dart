import 'package:core/models/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tonkatsu_box/features/settings/providers/profile_provider.dart';
import 'package:tonkatsu_box/features/settings/providers/settings_provider.dart';
import 'package:tonkatsu_box/features/settings/providers/watch_settings_provider.dart';

void main() {
  const String profileId = 'test-profile';
  final Profile testProfile = Profile(
    id: profileId,
    name: 'Test',
    color: '#EF7B44',
    createdAt: DateTime(2026),
  );

  Future<ProviderContainer> createContainer({
    Map<String, Object> initialPrefs = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentProfileProvider.overrideWithValue(testProfile),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('WatchSettingsState', () {
    test('defaults point at the local Docker ports', () {
      const WatchSettingsState state = WatchSettingsState();
      expect(state.jacRedUrl, 'http://127.0.0.1:9117');
      expect(state.torrServerUrl, 'http://127.0.0.1:8090');
      expect(state.jacRedApiKey, isEmpty);
      expect(state.isConfigured, isTrue);
    });

    test('isConfigured needs both URLs', () {
      expect(const WatchSettingsState(jacRedUrl: '').isConfigured, isFalse);
      expect(const WatchSettingsState(torrServerUrl: '').isConfigured, isFalse);
    });

    test('copyWith replaces only the given fields', () {
      final WatchSettingsState state = const WatchSettingsState().copyWith(
        jacRedApiKey: 'k',
      );
      expect(state.jacRedApiKey, 'k');
      expect(state.jacRedUrl, kDefaultJacRedUrl);
    });
  });

  group('WatchSettingsNotifier', () {
    test('build falls back to defaults on empty prefs', () async {
      final ProviderContainer container = await createContainer();
      final WatchSettingsState state = container.read(watchSettingsProvider);
      expect(state.jacRedUrl, kDefaultJacRedUrl);
      expect(state.torrServerUrl, kDefaultTorrServerUrl);
    });

    test('build reads stored per-profile values', () async {
      final ProviderContainer container = await createContainer(
        initialPrefs: <String, Object>{
          WatchSettingsKeys.jacRedUrl(profileId): 'http://nas:9117',
          WatchSettingsKeys.jacRedApiKey(profileId): 'secret',
          WatchSettingsKeys.torrServerUrl(profileId): 'http://nas:8090',
        },
      );
      final WatchSettingsState state = container.read(watchSettingsProvider);
      expect(state.jacRedUrl, 'http://nas:9117');
      expect(state.jacRedApiKey, 'secret');
      expect(state.torrServerUrl, 'http://nas:8090');
    });

    test('setJacRedUrl normalizes and persists', () async {
      final ProviderContainer container = await createContainer();
      await container
          .read(watchSettingsProvider.notifier)
          .setJacRedUrl(' 192.168.1.5:9117/ ');

      expect(
        container.read(watchSettingsProvider).jacRedUrl,
        'http://192.168.1.5:9117',
      );
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(WatchSettingsKeys.jacRedUrl(profileId)),
        'http://192.168.1.5:9117',
      );
    });

    test(
      'an emptied URL stays empty instead of reverting to the default',
      () async {
        final ProviderContainer container = await createContainer();
        await container
            .read(watchSettingsProvider.notifier)
            .setTorrServerUrl('');

        expect(container.read(watchSettingsProvider).torrServerUrl, isEmpty);
        expect(container.read(watchSettingsProvider).isConfigured, isFalse);

        final ProviderContainer reloaded = await createContainer(
          initialPrefs: <String, Object>{
            WatchSettingsKeys.torrServerUrl(profileId): '',
          },
        );
        expect(reloaded.read(watchSettingsProvider).torrServerUrl, isEmpty);
      },
    );

    test('setJacRedApiKey trims and persists', () async {
      final ProviderContainer container = await createContainer();
      await container
          .read(watchSettingsProvider.notifier)
          .setJacRedApiKey('  abc  ');

      expect(container.read(watchSettingsProvider).jacRedApiKey, 'abc');
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(WatchSettingsKeys.jacRedApiKey(profileId)), 'abc');
    });
  });
}
