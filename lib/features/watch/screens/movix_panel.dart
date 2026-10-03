import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../../l10n/app_localizations.dart';

const String kMovixUrl = 'https://movix.ru/';
const Color _kBackground = Colors.black;
const double _kBarHeight = 44;
const Duration _kInitTimeout = Duration(seconds: 20);

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
    _controller.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
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
        ..add(
          _controller.loadingState.listen((LoadingState s) {
            if (mounted) setState(() => _loading = s == LoadingState.loading);
          }),
        );
      await _controller.loadUrl(kMovixUrl);
      if (mounted) setState(() => _ready = true);
    } on Object catch (e) {
      _log.warning('embedded browser is not available: $e');
      if (mounted) setState(() => _failed = true);
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
