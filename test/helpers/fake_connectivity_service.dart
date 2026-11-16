import 'dart:async';

import 'package:laantech_pos_task/configs/services/connectivity_services/connectivity_service.dart';

/// Scriptable connectivity: [emit] flips the reported network state.
class FakeConnectivityService implements ConnectivityService {
  final controller = StreamController<bool>.broadcast();
  bool online = true;
  bool get hasListener => controller.hasListener;

  void emit(bool value) {
    online = value;
    controller.add(value);
  }

  @override
  Stream<bool> get onlineChanges => controller.stream;

  @override
  Future<bool> get isOnline async => online;
}
