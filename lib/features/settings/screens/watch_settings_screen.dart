import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/jacred_api.dart';
import '../../../core/api/torrserver_api.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/sub_screen_title_bar.dart';
import '../../watch/providers/watch_providers.dart';
import '../providers/watch_settings_provider.dart';
import '../widgets/inline_text_field.dart';
import '../widgets/settings_group.dart';
import '../widgets/settings_tile.dart';
import '../widgets/status_dot.dart';

const double _desktopBreakpoint = 800;

class WatchSettingsScreen extends ConsumerStatefulWidget {
  /// [embedded] drops the back-arrow title bar when shown inside the catalog.
  const WatchSettingsScreen({this.embedded = false, super.key});

  final bool embedded;

  @override
  ConsumerState<WatchSettingsScreen> createState() =>
      _WatchSettingsScreenState();
}

class _WatchSettingsScreenState extends ConsumerState<WatchSettingsScreen> {
  bool _isChecking = false;
  String? _jacRedResult;
  bool _jacRedOk = false;
  String? _torrServerResult;
  bool _torrServerOk = false;

  Future<void> _checkBoth() async {
    final S l = S.of(context);
    final JacRedApi jacRed = ref.read(jacRedApiProvider);
    final TorrServerApi torrServer = ref.read(torrServerApiProvider);
    setState(() {
      _isChecking = true;
      _jacRedResult = null;
      _torrServerResult = null;
    });

    bool jacRedOk = false;
    String jacRedText;
    try {
      jacRedOk = await jacRed.ping();
      jacRedText = jacRedOk
          ? l.watchJacRedOk
          : l.watchCheckFailed(jacRed.baseUrl);
    } on JacRedApiException catch (e) {
      jacRedText = l.watchCheckFailed(e.message);
    }

    bool torrServerOk = false;
    String torrServerText;
    try {
      final String version = await torrServer.echo();
      torrServerOk = true;
      torrServerText = l.watchTorrServerOk(version);
    } on TorrServerApiException catch (e) {
      torrServerText = l.watchCheckFailed(e.message);
    }

    if (!mounted) return;
    setState(() {
      _isChecking = false;
      _jacRedOk = jacRedOk;
      _jacRedResult = jacRedText;
      _torrServerOk = torrServerOk;
      _torrServerResult = torrServerText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final WatchSettingsState settings = ref.watch(watchSettingsProvider);
    final WatchSettingsNotifier notifier = ref.read(
      watchSettingsProvider.notifier,
    );
    final bool isWide = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    return Column(
      children: <Widget>[
        if (!widget.embedded) SubScreenTitleBar(title: l.settingsWatch),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWide ? 600 : double.infinity,
              ),
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? AppSpacing.lg : AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                children: <Widget>[
                  SettingsGroup(
                    title: l.watchJacRedTitle,
                    children: <Widget>[
                      _field(
                        label: l.watchJacRedUrl,
                        value: settings.jacRedUrl,
                        placeholder: kDefaultJacRedUrl,
                        onChanged: notifier.setJacRedUrl,
                      ),
                      _field(
                        label: l.watchJacRedApiKey,
                        value: settings.jacRedApiKey,
                        obscureText: true,
                        onChanged: notifier.setJacRedApiKey,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SettingsGroup(
                    title: l.watchTorrServerTitle,
                    children: <Widget>[
                      _field(
                        label: l.watchTorrServerUrl,
                        value: settings.torrServerUrl,
                        placeholder: kDefaultTorrServerUrl,
                        onChanged: notifier.setTorrServerUrl,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SettingsGroup(
                    title: l.catalogTitle,
                    children: <Widget>[
                      _field(
                        label: l.watchTwitchClientId,
                        value: settings.twitchClientId,
                        obscureText: true,
                        onChanged: notifier.setTwitchClientId,
                      ),
                      _field(
                        label: l.watchTwitchClientSecret,
                        value: settings.twitchClientSecret,
                        obscureText: true,
                        onChanged: notifier.setTwitchClientSecret,
                      ),
                      _field(
                        label: l.watchYoutubeBrowser,
                        value: settings.youtubeBrowser,
                        placeholder: kDefaultYoutubeBrowser,
                        onChanged: notifier.setYoutubeBrowser,
                      ),
                      _field(
                        label: l.watchIptvUrl,
                        value: settings.iptvUrl,
                        placeholder: 'https://…/playlist.m3u',
                        obscureText: true,
                        onChanged: notifier.setIptvUrl,
                      ),
                      _field(
                        label: l.watchCatalogUrl,
                        value: settings.catalogUrl,
                        placeholder: kDefaultCatalogUrl,
                        onChanged: notifier.setCatalogUrl,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SettingsGroup(
                    title: l.watchPlayerTitle,
                    children: <Widget>[
                      SettingsTile(
                        title: l.watchPlayerTitle,
                        value: _playerLabel(l, settings.player),
                        onTap: () => _pickPlayer(l, settings.player),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildCheck(l),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _playerLabel(S l, WatchPlayer player) => switch (player) {
    WatchPlayer.auto => l.watchPlayerAuto,
    WatchPlayer.mpcBe => 'MPC-BE', // proper noun
    WatchPlayer.mpcHc => 'MPC-HC', // proper noun
    WatchPlayer.vlc => 'VLC', // proper noun
    WatchPlayer.builtIn => l.watchPlayerBuiltIn,
  };

  void _pickPlayer(S l, WatchPlayer current) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: Text(l.watchPlayerTitle),
        children: <Widget>[
          for (final WatchPlayer player in WatchPlayer.values)
            SimpleDialogOption(
              onPressed: () {
                ref.read(watchSettingsProvider.notifier).setPlayer(player);
                Navigator.pop(dialogContext);
              },
              child: Row(
                children: <Widget>[
                  if (current == player)
                    Icon(Icons.check, size: 18, color: AppColors.brand)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Text(_playerLabel(l, player)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? placeholder,
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: InlineTextField(
        label: label,
        value: value,
        placeholder: placeholder,
        obscureText: obscureText,
        compact: true,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildCheck(S l) {
    return SettingsGroup(
      title: l.watchTestConnection,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StatusDot(
                label: _isChecking
                    ? l.watchChecking
                    : (_jacRedResult ?? 'JacRed'), // proper noun
                type: _statusOf(_jacRedResult, _jacRedOk),
              ),
              const SizedBox(height: AppSpacing.sm),
              StatusDot(
                label: _isChecking
                    ? l.watchChecking
                    : (_torrServerResult ?? 'TorrServer'), // proper noun
                type: _statusOf(_torrServerResult, _torrServerOk),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSpacing.buttonHeightCompact),
                  ),
                  onPressed: _isChecking ? null : _checkBoth,
                  icon: const Icon(Icons.sync, size: 18),
                  label: Text(l.watchTestConnection),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  StatusType _statusOf(String? result, bool ok) {
    if (_isChecking) return StatusType.warning;
    if (result == null) return StatusType.inactive;
    return ok ? StatusType.success : StatusType.error;
  }
}
