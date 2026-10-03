import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../l10n/app_localizations.dart';

const String kMovixUrl = 'https://movix.ru/';
const Color _kBackground = Colors.black;
const double _kBarHeight = 44;
const Duration _kInitTimeout = Duration(seconds: 20);
const String _kProbeScript =
    'JSON.stringify({t: document.title, s: document.readyState, '
    'n: document.body ? document.body.innerText.length : -1, '
    'x: document.body ? document.body.innerText.slice(0, 160) : "", '
    'w: window.innerWidth, h: window.innerHeight})';

// Movix is a Russian service that answers 403 to foreign addresses, and the
// system proxy of a VPN client would send the embedded browser abroad.
const String _kDirectConnection = '--no-proxy-server';

final Logger _log = Logger('MovixPanel');

/// Movix inside the app through the system WebView2: the official player and
/// the user's own login, no streams are pulled out of it.
class MovixPanel extends StatefulWidget {
  const MovixPanel({super.key});

  @override
  State<MovixPanel> createState() => _MovixPanelState();
}

class _MovixPanelState extends State<MovixPanel> {
  final WebviewController _controller = WebviewController();
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _controllerStarted = false;
  bool _ready = false;
  bool _failed = false;
  bool _canGoBack = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final StreamSubscription<Object?> sub in _subscriptions) {
      sub.cancel();
    }
    // Disposing a controller that never started throws a LateInitializationError.
    if (_controllerStarted) _controller.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      try {
        await WebviewController.initializeEnvironment(
          additionalArguments: _kDirectConnection,
        ).timeout(_kInitTimeout);
      } on PlatformException catch (e) {
        // A second visit finds the environment from the first one.
        _log.info('browser environment already exists: ${e.code}');
      }
      _controllerStarted = true;
      await _controller.initialize().timeout(_kInitTimeout);
      await _controller.setBackgroundColor(_kBackground);
      // Login and payment pages open pop-ups; keeping them in this view keeps
      // the session in one place.
      await _controller.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.sameWindow,
      );
      _subscriptions
        ..add(
          _controller.historyChanged.listen((HistoryChanged h) {
            if (mounted) setState(() => _canGoBack = h.canGoBack);
          }),
        )
        ..add(_controller.loadingState.listen(_onLoadingState))
        ..add(
          _controller.onLoadError.listen(
            (WebErrorStatus e) => _log.warning('load error: ${e.name}'),
          ),
        )
        ..add(_controller.url.listen((String u) => _log.info('url: $u')))
        ..add(_controller.title.listen((String t) => _log.info('title: $t')));
      // The texture only gets frames once the widget is on screen, so the page
      // starts loading after the first build that shows it.
      if (!mounted) return;
      setState(() => _ready = true);
      await WidgetsBinding.instance.endOfFrame;
      await _controller.loadUrl(kMovixUrl);
    } on Object catch (e) {
      _log.warning('embedded browser is not available: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _onLoadingState(LoadingState state) async {
    _log.info('loading: ${state.name}');
    if (mounted) setState(() => _loading = state == LoadingState.loading);
    if (state != LoadingState.navigationCompleted) return;
    try {
      final Object? probe = await _controller.executeScript(_kProbeScript);
      _log.info('page probe: $probe');
    } on Object catch (e) {
      _log.warning('page probe failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            S.of(context).watchMovixUnavailable,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return Column(
      children: <Widget>[
        SizedBox(
          height: _kBarHeight,
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: _canGoBack ? _controller.goBack : null,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _controller.reload,
              ),
              IconButton(
                icon: const Icon(Icons.home_outlined, size: 20),
                onPressed: () => _controller.loadUrl(kMovixUrl),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 20),
                onPressed: () => launchUrl(Uri.parse(kMovixUrl)),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: Webview(_controller)),
      ],
    );
  }
}
