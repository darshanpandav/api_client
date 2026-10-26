enum ApiErrorType {
  /// No connection, DNS failure, connection refused, bad certificate.
  network,
  timeout,
  cancelled,

  /// 400
  badRequest,

  /// 401
  unauthorized,

  /// 403
  forbidden,

  /// 404
  notFound,

  /// Any other 4xx (or unexpected non-2xx) status.
  httpError,

  /// 5xx
  server,

  /// The response arrived but could not be converted by the parser.
  parse,
  unknown,
}

/// The only exception type thrown by [ApiClient]. Catch this in your UI.
class ApiException implements Exception {
  ApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.data,
    this.error,
    this.stackTrace,
  });

  /// Builds an exception from a non-2xx response.
  factory ApiException.fromResponse(int statusCode, dynamic data) {
    return ApiException(
      type: _typeForStatus(statusCode),
      message: _extractMessage(statusCode, data),
      statusCode: statusCode,
      data: data,
    );
  }

  final ApiErrorType type;

  /// Human-readable message, taken from the server response when possible.
  final String message;
  final int? statusCode;

  /// Raw response body, if any.
  final dynamic data;

  /// Underlying error (DioException, ClientException, TimeoutException, ...).
  final Object? error;
  final StackTrace? stackTrace;

  bool get isNetworkError =>
      type == ApiErrorType.network || type == ApiErrorType.timeout;

  static ApiErrorType _typeForStatus(int code) {
    if (code >= 500) return ApiErrorType.server;
    return switch (code) {
      400 => ApiErrorType.badRequest,
      401 => ApiErrorType.unauthorized,
      403 => ApiErrorType.forbidden,
      404 => ApiErrorType.notFound,
      408 => ApiErrorType.timeout,
      _ => ApiErrorType.httpError,
    };
  }

  static String _extractMessage(int code, dynamic data) {
    if (data is Map) {
      for (final key in const ['message', 'error', 'detail', 'msg']) {
        final value = data[key];
        if (value is String && value.isNotEmpty) return value;
      }
    }
    if (data is String && data.isNotEmpty && data.length <= 200) return data;
    return 'Request failed with status code $code';
  }

  @override
  String toString() {
    final status = statusCode == null ? '' : ' $statusCode';
    return 'ApiException(${type.name}$status): $message';
  }
}
