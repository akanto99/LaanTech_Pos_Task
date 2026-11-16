import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports whether the device has a network interface up (Wi-Fi, mobile,
/// ethernet, VPN). That does not prove the internet or the API is reachable,
/// so callers must still treat request failures as the source of truth.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Emits only when the online/offline state actually flips.
  Stream<bool> get onlineChanges => _connectivity.onConnectivityChanged.map(_hasNetwork).distinct();

  Future<bool> get isOnline async => _hasNetwork(await _connectivity.checkConnectivity());

  static bool _hasNetwork(List<ConnectivityResult> results) => results.any((result) => result != ConnectivityResult.none);
}
