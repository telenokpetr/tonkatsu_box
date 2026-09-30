import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/service_url.dart';
import 'profile_provider.dart';
import 'settings_provider.dart';

abstract class WatchSettingsKeys {
  static String jacRedUrl(String profileId) => 'watch_jacred_url_$profileId';

  static String jacRedApiKey(String profileId) =>
      'watch_jacred_api_key_$profileId';

  static String torrServerUrl(String profileId) =>
      'watch_torrserver_url_$profileId';
}

/// Both services usually run on the same PC as the app (Docker), so the
/// defaults work without touching Settings.
const String kDefaultJacRedUrl = 'http://127.0.0.1:9117';
const String kDefaultTorrServerUrl = 'http://127.0.0.1:8090';

class WatchSettingsState {
  const WatchSettingsState({
    this.jacRedUrl = kDefaultJacRedUrl,
    this.jacRedApiKey = '',
    this.torrServerUrl = kDefaultTorrServerUrl,
  });

  final String jacRedUrl;
  final String jacRedApiKey;
  final String torrServerUrl;

  bool get isConfigured => jacRedUrl.isNotEmpty && torrServerUrl.isNotEmpty;

  WatchSettingsState copyWith({
    String? jacRedUrl,
    String? jacRedApiKey,
    String? torrServerUrl,
  }) {
    return WatchSettingsState(
      jacRedUrl: jacRedUrl ?? this.jacRedUrl,
      jacRedApiKey: jacRedApiKey ?? this.jacRedApiKey,
      torrServerUrl: torrServerUrl ?? this.torrServerUrl,
    );
  }
}

final NotifierProvider<WatchSettingsNotifier, WatchSettingsState>
watchSettingsProvider =
    NotifierProvider<WatchSettingsNotifier, WatchSettingsState>(
      WatchSettingsNotifier.new,
    );

class WatchSettingsNotifier extends Notifier<WatchSettingsState> {
  late SharedPreferences _prefs;
  late String _profileId;

  @override
  WatchSettingsState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    _profileId = ref.watch(currentProfileProvider).id;
    return WatchSettingsState(
      jacRedUrl:
          _prefs.getString(WatchSettingsKeys.jacRedUrl(_profileId)) ??
          kDefaultJacRedUrl,
      jacRedApiKey:
          _prefs.getString(WatchSettingsKeys.jacRedApiKey(_profileId)) ?? '',
      torrServerUrl:
          _prefs.getString(WatchSettingsKeys.torrServerUrl(_profileId)) ??
          kDefaultTorrServerUrl,
    );
  }

  /// An empty string is stored as-is: it means "turned off", while a missing
  /// key falls back to the default.
  Future<void> setJacRedUrl(String value) async {
    final String url = normalizeServiceUrl(value);
    await _prefs.setString(WatchSettingsKeys.jacRedUrl(_profileId), url);
    state = state.copyWith(jacRedUrl: url);
  }

  Future<void> setJacRedApiKey(String value) async {
    final String key = value.trim();
    await _prefs.setString(WatchSettingsKeys.jacRedApiKey(_profileId), key);
    state = state.copyWith(jacRedApiKey: key);
  }

  Future<void> setTorrServerUrl(String value) async {
    final String url = normalizeServiceUrl(value);
    await _prefs.setString(WatchSettingsKeys.torrServerUrl(_profileId), url);
    state = state.copyWith(torrServerUrl: url);
  }
}
