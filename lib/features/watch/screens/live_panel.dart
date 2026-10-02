import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/extensions/snackbar_extension.dart';
import '../../settings/providers/settings_provider.dart';
import '../play_stream.dart';
import '../stream_resolver.dart';

const Duration _kErrorSnack = Duration(seconds: 8);

String _favoritesKey(LiveService service) => 'watch_live_favs_${service.name}';

/// A link or channel box for YouTube, Twitch or Kick, with saved channels.
class LivePanel extends ConsumerStatefulWidget {
  const LivePanel({required this.service, super.key});

  final LiveService service;

  @override
  ConsumerState<LivePanel> createState() => _LivePanelState();
}

class _LivePanelState extends ConsumerState<LivePanel> {
  final TextEditingController _input = TextEditingController();
  late List<String> _favorites;
  bool _busy = false;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  void initState() {
    super.initState();
    _favorites =
        _prefs.getStringList(_favoritesKey(widget.service)) ?? <String>[];
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _saveFavorites() =>
      _prefs.setStringList(_favoritesKey(widget.service), _favorites);

  Future<void> _addFavorite() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _favorites.contains(text)) return;
    setState(() => _favorites = <String>[..._favorites, text]);
    await _saveFavorites();
  }

  Future<void> _removeFavorite(String text) async {
    setState(
      () => _favorites = _favorites.where((String f) => f != text).toList(),
    );
    await _saveFavorites();
  }

  Future<void> _open(String text) async {
    final String input = text.trim();
    if (input.isEmpty || _busy) return;
    final S l = S.of(context);
    setState(() => _busy = true);
    try {
      final String url = await ref
          .read(streamResolverProvider)
          .resolve(widget.service, input);
      if (!mounted) return;
      await playStream(context, ref, url: url, title: input);
    } on StreamResolveException catch (e) {
      if (!mounted) return;
      final LiveTool? tool = e.missingTool;
      context.showSnack(
        tool != null
            ? l.liveToolMissing(tool.name, tool.wingetId)
            : l.liveResolveFailed(e.message),
        type: SnackType.error,
        duration: _kErrorSnack,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      context.showSnack(
        l.liveResolveFailed('$e'),
        type: SnackType.error,
        duration: _kErrorSnack,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final S l = S.of(context);
    final bool youtube = widget.service == LiveService.youtube;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: youtube
                          ? l.liveInputYoutube
                          : l.liveInputChannel,
                      prefixIcon: const Icon(Icons.link, size: 18),
                    ),
                    onSubmitted: _open,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: _busy ? null : () => _open(_input.text),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.liveOpen),
              ),
              IconButton(
                tooltip: l.liveSave,
                icon: const Icon(Icons.star_outline),
                onPressed: _addFavorite,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_favorites.isNotEmpty) ...<Widget>[
            Text(l.liveFavorites),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String fav in _favorites)
                  InputChip(
                    key: ValueKey<String>(fav),
                    label: Text(fav),
                    onPressed: () => _open(fav),
                    onDeleted: () => _removeFavorite(fav),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
