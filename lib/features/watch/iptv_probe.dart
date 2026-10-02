import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_dio.dart';
import '../../core/api/iptv_api.dart';
import 'providers/watch_providers.dart';

const int _kWorkers = 24;
const int _kPublishEvery = 8;
const Duration _kProbeTimeout = Duration(seconds: 8);

/// Whether a stream URL answers at all. Free playlists are full of dead links,
/// and a player reports those as "file not found".
Future<bool> probeStream(Dio dio, String url) async {
  if (!url.startsWith('http')) return false;
  final CancelToken cancel = CancelToken();
  try {
    await dio
        .get<ResponseBody>(
          url,
          cancelToken: cancel,
          options: Options(
            headers: <String, String>{'Range': 'bytes=0-1023'},
            validateStatus: (int? s) => s != null && s < 400,
          ),
        )
        .timeout(_kProbeTimeout);
    return true;
  } on Exception {
    return false;
  } finally {
    // A live TS stream never ends; the headers were all that was needed.
    cancel.cancel();
  }
}

class IptvProbeState {
  const IptvProbeState({
    required this.alive,
    required this.done,
    required this.total,
  });

  final Set<String> alive;
  final int done;
  final int total;

  bool get finished => done >= total;
}

/// Checks every channel in the background and publishes the answering ones as
/// they are found. Kept for the session so switching tabs does not restart it.
final StreamProvider<IptvProbeState> iptvProbeProvider =
    StreamProvider<IptvProbeState>((Ref ref) async* {
      final List<IptvChannel> channels = await ref.watch(
        iptvChannelsProvider.future,
      );
      final Dio dio = createApiDio(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 6),
        responseType: ResponseType.stream,
      );
      final Queue<String> queue = Queue<String>.of(
        channels.map((IptvChannel c) => c.url),
      );
      final Set<String> alive = <String>{};
      int done = 0;
      final StreamController<IptvProbeState> out =
          StreamController<IptvProbeState>();
      IptvProbeState snapshot() => IptvProbeState(
        alive: Set<String>.of(alive),
        done: done,
        total: channels.length,
      );

      Future<void> worker() async {
        while (queue.isNotEmpty) {
          final String url = queue.removeFirst();
          if (await probeStream(dio, url)) alive.add(url);
          done++;
          if (done % _kPublishEvery == 0 || done == channels.length) {
            if (!out.isClosed) out.add(snapshot());
          }
        }
      }

      out.add(snapshot());
      unawaited(
        Future.wait(<Future<void>>[
          for (int i = 0; i < _kWorkers; i++) worker(),
        ]).whenComplete(out.close),
      );
      yield* out.stream;
    });
