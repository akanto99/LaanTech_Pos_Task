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
    final monitor = TransferNetworkMonitor(connectivity: connectivity);
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

  test('nextChange completes on the next connectivity change, or on dispose', () async {
    final connectivity = FakeConnectivityService();
    final monitor = TransferNetworkMonitor(connectivity: connectivity);
    await monitor.start();

    var changed = false;
    unawaited(monitor.nextChange().then((_) => changed = true));
    await pumpEventQueue();
    expect(changed, isFalse);
    connectivity.emit(false);
    await pumpEventQueue();
    expect(changed, isTrue);

    var released = false;
    unawaited(monitor.nextChange().then((_) => released = true));
    await monitor.dispose();
    await pumpEventQueue();
    expect(released, isTrue, reason: 'waiters are never left hanging');
  });

  test('without a connectivity plugin it assumes online', () async {
    final monitor = TransferNetworkMonitor(connectivity: _BrokenConnectivity());
    await monitor.start();
    expect(monitor.isOnline, isTrue);
  });
}
