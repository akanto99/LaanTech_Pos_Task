import 'package:laantech_pos_task/data/response/status.dart';

class ApiResponse<T> {
  final Status status;
  final T? data;
  final String? message;

  const ApiResponse.loading()
    : status = Status.loading,
      data = null,
      message = null;

  const ApiResponse.completed(this.data)
    : status = Status.completed,
      message = null;

  const ApiResponse.error(this.message) : status = Status.error, data = null;
}
