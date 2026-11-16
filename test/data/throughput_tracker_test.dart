import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/data/transfer/throughput_tracker.dart';
import 'package:laantech_pos_task/model/transfer/network_health.dart';

void main() {
  late DateTime now;
  late ThroughputTracker tracker;

  void advance(Duration by) => now = now.add(by);

  /// Feeds [bytesPerSecond] for [seconds], one progress event per second.
  void flow(int bytesPerSecond, int seconds, {int from = 0}) {
    var bytes = from;
    for (var i = 0; i < seconds; i++) {
      advance(const Duration(seconds: 1));
      bytes += bytesPerSecond;
      tracker.record(bytes);
    }
  }

  setUp(() {
    now = DateTime(2026);
    tracker = ThroughputTracker(startBytes: 0, clock: () => now);
  });

  test('a healthy transfer is good and reports its real speed', () {
    flow(500 * 1024, 5);
    expect(tracker.classify(NetworkHealth.good), NetworkHealth.good);
    expect(tracker.bytesPerSecond, 500 * 1024);
  });

  test('nothing is classified during warm-up, even with no data yet', () {
    advance(const Duration(seconds: 2));
    expect(tracker.classify(NetworkHealth.good), NetworkHealth.good);
  });

  test('slow but moving data is poor, not stalled or offline', () {
    flow(8 * 1024, 6);
    expect(tracker.classify(NetworkHealth.good), NetworkHealth.poor);
    expect(tracker.bytesPerSecond, 8 * 1024);
  });

  test('a single slow chunk inside a healthy window stays good', () {
    flow(200 * 1024, 6);
    advance(const Duration(seconds: 2)); // one late progress event
    tracker.record(6 * 200 * 1024 + 1024);
    expect(tracker.classify(NetworkHealth.good), NetworkHealth.good);
  });

  test('hysteresis: poor needs a clearly better rate to become good again', () {
    flow(8 * 1024, 10);
    expect(tracker.classify(NetworkHealth.good), NetworkHealth.poor);
    // 48 KiB/s is above the poor threshold but below the good threshold.
    flow(48 * 1024, 10, from: 80 * 1024);
    expect(tracker.classify(NetworkHealth.poor), NetworkHealth.poor);
    expect(tracker.classify(NetworkHealth.good), NetworkHealth.good);
  });

  test('no new bytes for the stall threshold is stalled, and speed decays', () {
    flow(100 * 1024, 4);
    advance(AppConfig.stallWarningAfter);
    expect(tracker.classify(NetworkHealth.good), NetworkHealth.stalled);
    expect(tracker.bytesPerSecond, 0);
  });

  test('an upload waiting for the server response is not a stall', () {
    flow(100 * 1024, 4);
    advance(const Duration(seconds: 30));
    expect(tracker.classify(NetworkHealth.good, finished: true), NetworkHealth.good);
  });

  test('a resumed attempt shows "resumed" briefly, then its real health', () {
    tracker = ThroughputTracker(startBytes: 1000, clock: () => now, resumed: true);
    flow(200 * 1024, 3, from: 1000);
    expect(tracker.classify(NetworkHealth.resumed), NetworkHealth.resumed);
    flow(200 * 1024, 3, from: 1000 + 600 * 1024);
    expect(tracker.classify(NetworkHealth.resumed), NetworkHealth.good);
  });
}
