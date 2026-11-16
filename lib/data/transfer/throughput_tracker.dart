import 'dart:collection';

import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/model/transfer/network_health.dart';

/// Measures one transfer attempt from its real byte progress and classifies
/// the link as good, poor or stalled.
///
/// Only actual bytes moved over elapsed time are used. A slow but moving
/// transfer is "poor", never "offline"; a transfer with no new bytes for
/// [AppConfig.stallWarningAfter] is "stalled". Connectivity (offline,
/// reconnecting) is decided by the caller, not here.
class ThroughputTracker {
  ThroughputTracker({required int startBytes, DateTime Function()? clock, this.resumed = false}) : _clock = clock ?? DateTime.now {
    _startedAt = _clock();
    _lastChangeAt = _startedAt;
    _samples.add((at: _startedAt, bytes: startBytes));
  }

  final DateTime Function() _clock;

  /// The attempt follows a connection loss, so it starts as [NetworkHealth.resumed].
  final bool resumed;

  late final DateTime _startedAt;
  late DateTime _lastChangeAt;
  final _samples = Queue<({DateTime at, int bytes})>();

  int get _bytes => _samples.last.bytes;

  /// How long no new bytes have been transferred.
  Duration get idle => _clock().difference(_lastChangeAt);

  void record(int bytes) {
    final now = _clock();
    if (bytes != _bytes) _lastChangeAt = now;
    _samples.add((at: now, bytes: bytes));
    _prune(now);
  }

  /// Average rate over the window, measured up to *now*: when data stops
  /// arriving the rate decays instead of freezing at the last good value.
  int get bytesPerSecond {
    final now = _clock();
    _prune(now);
    final first = _samples.first;
    final elapsed = now.difference(first.at).inMilliseconds;
    if (elapsed <= 0) return 0;
    return ((_bytes - first.bytes) * 1000 / elapsed).round().clamp(0, 1 << 62);
  }

  /// [current] is the state shown now, used for hysteresis.
  /// [finished] means every byte is sent and only the response is awaited,
  /// so silence is expected and is not a stall.
  NetworkHealth classify(NetworkHealth current, {bool finished = false}) {
    final now = _clock();
    final sinceStart = now.difference(_startedAt);
    final fallback = resumed && sinceStart < AppConfig.resumedNoticeDuration ? NetworkHealth.resumed : NetworkHealth.good;
    if (finished) return current == NetworkHealth.stalled ? fallback : current;
    if (idle >= AppConfig.stallWarningAfter) return NetworkHealth.stalled;
    if (sinceStart < AppConfig.networkHealthWarmup) return fallback;

    final rate = bytesPerSecond;
    final wasSlow = current == NetworkHealth.poor || current == NetworkHealth.stalled;
    if (rate < AppConfig.poorThroughputBytesPerSecond || (wasSlow && rate < AppConfig.goodThroughputBytesPerSecond)) {
      return NetworkHealth.poor;
    }
    return fallback;
  }

  /// Keeps samples inside the window plus the one just before it, so the
  /// window always has a baseline even when progress events are sparse.
  void _prune(DateTime now) {
    final windowStart = now.subtract(AppConfig.throughputWindow);
    while (_samples.length > 1 && !_samples.elementAt(1).at.isAfter(windowStart)) {
      _samples.removeFirst();
    }
  }
}
