import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/service_url.dart';
import '../../../shared/constants/platform_features.dart';
import 'profile_provider.dart';
import 'settings_provider.dart';

abstract class WatchSettingsKeys {
  static String jacRedUrl(String profileId) => 'watch_jacred_url_$profileId';

  static String jacRedApiKey(String profileId) =>
      'watch_jacred_api_key_$profileId';

  static String torrServerUrl(String profileId) =>
      'watch_torrserver_url_$profileId';

  static String player(String profileId) => 'watch_player_$profileId';
}

// `auto` takes the first external player found: MPC-BE, MPC-HC, VLC.
enum WatchPlayer { auto, mpcBe, mpcHc, vlc, builtIn }

/// On a PC both services usually run next to the app (Docker), so these
/// defaults work untouched; a phone starts empty, see `_defaultFor`.
const String kDefaultJacRedUrl = 'http://127.0.0.1:9117';
const String kDefaultTorrServerUrl = 'http://127.0.0.1:8090';

class WatchSettingsState {
  const WatchSettingsState({
    this.jacRedUrl = '',
    this.jacRedApiKey = '',
    this.torrServerUrl = '',
    this.player = WatchPlayer.auto,
  });

  final String jacRedUrl;
  final String jacRedApiKey;
  final String torrServerUrl;
  final WatchPlayer player;

  bool get isConfigured => jacRedUrl.isNotEmpty && torrServerUrl.isNotEmpty;

  WatchSettingsState copyWith({
    String? jacRedUrl,
    String? jacRedApiKey,
    String? torrServerUrl,
    WatchPlayer? player,
  }) {
    return WatchSettingsState(
      jacRedUrl: jacRedUrl ?? this.jacRedUrl,
      jacRedApiKey: jacRedApiKey ?? this.jacRedApiKey,
      torrServerUrl: torrServerUrl ?? this.torrServerUrl,
      player: player ?? this.player,
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
          _defaultFor(kDefaultJacRedUrl),
      jacRedApiKey:
          _prefs.getString(WatchSettingsKeys.jacRedApiKey(_profileId)) ?? '',
      torrServerUrl:
          _prefs.getString(WatchSettingsKeys.torrServerUrl(_profileId)) ??
          _defaultFor(kDefaultTorrServerUrl),
      player:
          WatchPlayer.values.asNameMap()[_prefs.getString(
            WatchSettingsKeys.player(_profileId),
          )] ??
          WatchPlayer.auto,
    );
  }

  // 127.0.0.1 on a phone is the phone itself, never the PC with the servers.
  String _defaultFor(String desktopUrl) => kIsMobile ? '' : desktopUrl;

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

  Future<void> setPlayer(WatchPlayer value) async {
    await _prefs.setString(WatchSettingsKeys.player(_profileId), value.name);
    state = state.copyWith(player: value);
  }
}
