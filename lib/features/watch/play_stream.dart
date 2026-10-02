import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:logging/logging.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/extensions/snackbar_extension.dart';
import '../settings/providers/watch_settings_provider.dart';
import 'external_player.dart';
import 'screens/player_screen.dart';

final Logger _log = Logger('PlayStream');

/// Plays a ready stream URL in the chosen player; a missing external player
/// falls back to the built-in one.
Future<void> playStream(
  BuildContext context,
  WidgetRef ref, {
  required String url,
  required String title,
}) async {
  final S l = S.of(context);
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  final WatchPlayer choice = ref.read(watchSettingsProvider).player;
  _log.info('play "$title" <- ${describeStreamUrl(url)} via ${choice.name}');
  if (choice != WatchPlayer.builtIn) {
    final bool opened = await ref
        .read(externalPlayerProvider)
        .launch(choice: choice, urls: <String>[url], titles: <String>[title]);
    if (opened) return;
    if (!context.mounted) return;
    context.showSnack(l.watchVlcMissing, type: SnackType.error);
  }
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (BuildContext context) => PlayerScreen(url: url, title: title),
    ),
  );
}
