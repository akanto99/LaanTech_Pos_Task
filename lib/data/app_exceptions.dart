class AppException implements Exception {
  final String message;

  /// Transient failures (network, timeouts, 5xx) may be retried automatically;
  /// everything else is permanent and needs user action.
  final bool retryable;

  const AppException(this.message, {this.retryable = false});

  @override
  String toString() => message;
}

class FetchDataException extends AppException {
  const FetchDataException(super.message) : super(retryable: true);
}

/// The network itself failed (no route, connection lost, timed out or
/// stalled), as opposed to the server answering with an error. Transfers wait
/// for a usable connection before retrying these.
class NetworkException extends FetchDataException {
  const NetworkException(super.message);
}

class BadRequestException extends AppException {
  const BadRequestException(super.message);
}

class UnauthorisedException extends AppException {
  const UnauthorisedException([super.message = 'Your session has expired. Please log in again.']);
}

class InvalidInputException extends AppException {
  const InvalidInputException(super.message);
}

class StorageException extends AppException {
  const StorageException(super.message);
}

class CancelledException extends AppException {
  const CancelledException() : super('Cancelled');
}
