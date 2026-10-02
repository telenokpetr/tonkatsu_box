import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/watch/screens/tv_shell.dart';
import '../constants/platform_features.dart';
import 'app_shell.dart';

/// Whether the app opens on the TV-style shell. A provider so the tests of the
/// classic Tonkatsu Box shell can switch it off on a Windows machine.
final Provider<bool> tvShellEnabledProvider = Provider<bool>(
  (Ref ref) => kWatchEnabled,
);

/// What the app opens on: the TV-style shell where the Watch feature exists,
/// the full Tonkatsu Box shell elsewhere.
class RootShell extends ConsumerWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(tvShellEnabledProvider)
        ? const TvShell()
        : const AppShell();
  }
}
