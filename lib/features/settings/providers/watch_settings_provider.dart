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

  static String catalogUrl(String profileId) => 'watch_catalog_url_$profileId';

  static String iptvUrl(String profileId) => 'watch_iptv_url_$profileId';

  static String youtubeBrowser(String profileId) =>
      'watch_youtube_browser_$profileId';
}

// `auto` takes the first external player found: MPC-BE, MPC-HC, VLC.
enum WatchPlayer { auto, mpcBe, mpcHc, vlc, builtIn }

/// On a PC both services usually run next to the app (Docker), so these
/// defaults work untouched; a phone starts empty, see `_defaultFor`.
const String kDefaultJacRedUrl = 'http://127.0.0.1:9117';
const String kDefaultTorrServerUrl = 'http://127.0.0.1:8090';
const String kDefaultCatalogUrl = 'http://127.0.0.1:8099/catalog.json';
const String kDefaultYoutubeBrowser = 'vivaldi';

class WatchSettingsState {
  const WatchSettingsState({
    this.jacRedUrl = '',
    this.jacRedApiKey = '',
    this.torrServerUrl = '',
    this.player = WatchPlayer.auto,
    this.catalogUrl = '',
    this.iptvUrl = '',
    this.youtubeBrowser = kDefaultYoutubeBrowser,
  });

  final String jacRedUrl;
  final String jacRedApiKey;
  final String torrServerUrl;
  final WatchPlayer player;
  final String catalogUrl;

  /// A personal m3u playlist (an IPTV account); empty means the free list.
  final String iptvUrl;

  /// The browser whose YouTube login yt-dlp reads (`vivaldi`, `chrome`, ...).
  final String youtubeBrowser;

  bool get isConfigured => jacRedUrl.isNotEmpty && torrServerUrl.isNotEmpty;

  WatchSettingsState copyWith({
    String? jacRedUrl,
    String? jacRedApiKey,
    String? torrServerUrl,
    WatchPlayer? player,
    String? catalogUrl,
    String? iptvUrl,
    String? youtubeBrowser,
  }) {
    return WatchSettingsState(
      jacRedUrl: jacRedUrl ?? this.jacRedUrl,
      jacRedApiKey: jacRedApiKey ?? this.jacRedApiKey,
      torrServerUrl: torrServerUrl ?? this.torrServerUrl,
      player: player ?? this.player,
      catalogUrl: catalogUrl ?? this.catalogUrl,
      iptvUrl: iptvUrl ?? this.iptvUrl,
      youtubeBrowser: youtubeBrowser ?? this.youtubeBrowser,
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
      catalogUrl:
          _prefs.getString(WatchSettingsKeys.catalogUrl(_profileId)) ??
          _defaultFor(kDefaultCatalogUrl),
      iptvUrl: _prefs.getString(WatchSettingsKeys.iptvUrl(_profileId)) ?? '',
      youtubeBrowser:
          _prefs.getString(WatchSettingsKeys.youtubeBrowser(_profileId)) ??
          kDefaultYoutubeBrowser,
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

  Future<void> setCatalogUrl(String value) async {
    final String url = normalizeServiceUrl(value);
    await _prefs.setString(WatchSettingsKeys.catalogUrl(_profileId), url);
    state = state.copyWith(catalogUrl: url);
  }

  /// Kept verbatim apart from trimming: a playlist link carries a token that
  /// a URL normalizer must not touch.
  Future<void> setIptvUrl(String value) async {
    final String url = value.trim();
    await _prefs.setString(WatchSettingsKeys.iptvUrl(_profileId), url);
    state = state.copyWith(iptvUrl: url);
  }

  Future<void> setYoutubeBrowser(String value) async {
    final String browser = value.trim().toLowerCase();
    final String stored = browser.isEmpty ? kDefaultYoutubeBrowser : browser;
    await _prefs.setString(
      WatchSettingsKeys.youtubeBrowser(_profileId),
      stored,
    );
    state = state.copyWith(youtubeBrowser: stored);
  }
}
