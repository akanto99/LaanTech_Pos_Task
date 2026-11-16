import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/configs/services/connectivity_services/connectivity_service.dart';
import 'package:laantech_pos_task/data/transfer/transfer_network_monitor.dart';

import '../helpers/fake_connectivity_service.dart';

class _BrokenConnectivity implements ConnectivityService {
  @override
  Future<bool> get isOnline => Future.error(UnimplementedError('no plugin'));

  @override
  Stream<bool> get onlineChanges => const Stream.empty();
}

void main() {
  test('tracks connectivity with a single listener', () async {
    final connectivity = FakeConnectivityService()..online = false;
    final monitor = TransferNetworkMonitor(connectivity: connectivity, serverReachable: () async => true);
    await monitor.start();
    await monitor.start();

    expect(monitor.isOnline, isFalse);
    var online = false;
    unawaited(monitor.whenOnline().then((_) => online = true));
    await pumpEventQueue();
    expect(online, isFalse);

    connectivity.emit(true);
    await pumpEventQueue();
    expect(online, isTrue);
    expect(monitor.isOnline, isTrue);

    await monitor.dispose();
    expect(connectivity.hasListener, isFalse);
  });

  test('concurrent reachability checks share one request', () async {
    var probes = 0;
    final gate = Completer<bool>();
    final monitor = TransferNetworkMonitor(
      connectivity: FakeConnectivityService(),
      serverReachable: () {
        probes++;
        return gate.future;
      },
    );

    final results = [monitor.checkServer(), monitor.checkServer(), monitor.checkServer()];
    gate.complete(true);
    expect(await Future.wait(results), [true, true, true]);
    expect(probes, 1);

    // A later check sends a new request.
    await monitor.checkServer();
    expect(probes, 2);
  });

  test('a failing probe counts as unreachable', () async {
    final monitor = TransferNetworkMonitor(connectivity: FakeConnectivityService(), serverReachable: () => Future.error(Exception('boom')));
    expect(await monitor.checkServer(), isFalse);
  });

  test('without a connectivity plugin it assumes online', () async {
    final monitor = TransferNetworkMonitor(connectivity: _BrokenConnectivity(), serverReachable: () async => true);
    await monitor.start();
    expect(monitor.isOnline, isTrue);
  });
}
