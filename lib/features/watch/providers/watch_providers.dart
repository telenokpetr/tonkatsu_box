import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/jacred_api.dart';
import '../../../core/api/torrserver_api.dart';
import '../../settings/providers/watch_settings_provider.dart';
import '../watch_query.dart';

/// Rebuilt whenever the address or key changes in Settings.
final Provider<JacRedApi> jacRedApiProvider = Provider<JacRedApi>((Ref ref) {
  final WatchSettingsState settings = ref.watch(watchSettingsProvider);
  return JacRedApi(baseUrl: settings.jacRedUrl, apiKey: settings.jacRedApiKey);
});

final Provider<TorrServerApi> torrServerApiProvider = Provider<TorrServerApi>((
  Ref ref,
) {
  final WatchSettingsState settings = ref.watch(watchSettingsProvider);
  return TorrServerApi(baseUrl: settings.torrServerUrl);
});

final AutoDisposeFutureProviderFamily<List<JacRedTorrent>, WatchQuery>
watchResultsProvider = FutureProvider.autoDispose
    .family<List<JacRedTorrent>, WatchQuery>((Ref ref, WatchQuery query) {
      return ref
          .watch(jacRedApiProvider)
          .search(
            title: query.title,
            originalTitle: query.originalTitle,
            year: query.year,
            isSerial: query.isSerial,
          );
    });
