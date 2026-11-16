/// Network condition observed for a running transfer.
///
/// Kept separate from [TransferStatus] and from progress: health describes
/// the link, never how much of the file has been transferred. Values are
/// ordered from best to worst so the most severe one can be picked when
/// several transfers run at once.
enum NetworkHealth {
  /// Data is flowing at a healthy rate (or the attempt is still warming up).
  good,

  /// The transfer just started again after the connection came back.
  resumed,

  /// Data is still flowing, but slowly. The transfer is not interrupted.
  poor,

  /// The device is online but no data has moved for a while.
  stalled,

  /// The connection is back; checking the server is reachable before retrying.
  reconnecting,

  /// No usable network. Nothing is sent until it returns.
  offline;

  /// No request is in flight; the transfer is waiting for the network.
  bool get isWaiting => this == offline || this == reconnecting;

  /// The worst of [healths], or [good] when empty.
  static NetworkHealth worstOf(Iterable<NetworkHealth> healths) => healths.fold(good, (worst, health) => health.index > worst.index ? health : worst);
}
