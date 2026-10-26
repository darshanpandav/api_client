import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_config.dart';
import 'api_exception.dart';
import 'api_file.dart';
import 'api_logger.dart';

enum HttpMethod {
  get,
  post,
  put,
  patch,
  delete;

  String get value => name.toUpperCase();
}

/// How the response body should be returned.
enum ApiResponseType {
  /// Decoded JSON (Map / List). Falls back to a String if the body is not JSON.
  json,

  /// The body as a String.
  text,

  /// The raw bytes as a [Uint8List] (images, PDFs, any binary file).
  bytes,
}

/// Called with bytes transferred so far and the total (-1 if unknown).
typedef ApiProgressCallback = void Function(int count, int total);

/// Converts the response body into your model.
typedef JsonParser<T> = T Function(dynamic json);

/// Everything a transport needs to perform one request.
class ApiRequest {
  const ApiRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
    this.responseType = ApiResponseType.json,
    this.savePath,
    this.onSendProgress,
    this.onReceiveProgress,
  });

  final HttpMethod method;
  final Uri uri;
  final Map<String, String> headers;

  /// null, String, `List<int>`, [ApiFile], [ApiFormData], or anything
  /// JSON-encodable (Map, List, ...).
  final Object? body;
  final ApiResponseType responseType;

  /// When set, a 2xx response body is streamed to this file instead of
  /// being returned.
  final String? savePath;
  final ApiProgressCallback? onSendProgress;
  final ApiProgressCallback? onReceiveProgress;
}

/// Transport-level response returned by [ApiClient.send].
class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    this.data,
    this.headers = const {},
  });

  final int statusCode;

  /// Decoded according to [ApiRequest.responseType], or the save path
  /// for downloads.
  final dynamic data;
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Common interface for every HTTP backend.
///
/// URL building, headers, auth, logging, status checks and parsing live here.
/// Subclasses implement only [send] (the actual network call) and [close].
abstract class ApiClient {
  ApiClient(ApiConfig config)
      : _config = config,
        _authToken = config.authToken,
        _logger = _createLogger(config);

  ApiConfig _config;
  String? _authToken;
  ApiLogger _logger;

  ApiConfig get config => _config;
  String? get authToken => _authToken;

  /// Set after login, or pass `null` on logout.
  void setAuthToken(String? token) => _authToken = token;

  /// Replace the config at runtime (e.g. switch base URL or environment).
  void updateConfig(ApiConfig config) {
    _config = config;
    _logger = _createLogger(config);
    onConfigChanged();
  }

  // ---------- Public API ----------

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    JsonParser<T>? parser,
    ApiResponseType responseType = ApiResponseType.json,
    ApiProgressCallback? onReceiveProgress,
  }) =>
      request<T>(HttpMethod.get, path,
          query: query,
          headers: headers,
          parser: parser,
          responseType: responseType,
          onReceiveProgress: onReceiveProgress);

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    JsonParser<T>? parser,
    ApiResponseType responseType = ApiResponseType.json,
    ApiProgressCallback? onSendProgress,
    ApiProgressCallback? onReceiveProgress,
  }) =>
      request<T>(HttpMethod.post, path,
          body: body,
          query: query,
          headers: headers,
          parser: parser,
          responseType: responseType,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress);

  Future<T> put<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    JsonParser<T>? parser,
    ApiResponseType responseType = ApiResponseType.json,
    ApiProgressCallback? onSendProgress,
    ApiProgressCallback? onReceiveProgress,
  }) =>
      request<T>(HttpMethod.put, path,
          body: body,
          query: query,
          headers: headers,
          parser: parser,
          responseType: responseType,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress);

  Future<T> patch<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    JsonParser<T>? parser,
    ApiResponseType responseType = ApiResponseType.json,
    ApiProgressCallback? onSendProgress,
    ApiProgressCallback? onReceiveProgress,
  }) =>
      request<T>(HttpMethod.patch, path,
          body: body,
          query: query,
          headers: headers,
          parser: parser,
          responseType: responseType,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress);

  Future<T> delete<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    JsonParser<T>? parser,
    ApiResponseType responseType = ApiResponseType.json,
  }) =>
      request<T>(HttpMethod.delete, path,
          body: body,
          query: query,
          headers: headers,
          parser: parser,
          responseType: responseType);

  /// Downloads [path] and streams it into the file at [savePath].
  /// Returns [savePath]. Not supported on Flutter Web: use
  /// `get(path, responseType: ApiResponseType.bytes)` there instead.
  Future<String> download(
    String path,
    String savePath, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    ApiProgressCallback? onReceiveProgress,
  }) {
    return _execute<String>(
      ApiRequest(
        method: HttpMethod.get,
        uri: buildUri(path, query),
        headers: buildHeaders(headers),
        responseType: ApiResponseType.bytes,
        savePath: savePath,
        onReceiveProgress: onReceiveProgress,
      ),
      null,
    );
  }

  /// Sends a request and returns the parsed result.
  /// Throws [ApiException] on any failure.
  Future<T> request<T>(
    HttpMethod method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    JsonParser<T>? parser,
    ApiResponseType responseType = ApiResponseType.json,
    ApiProgressCallback? onSendProgress,
    ApiProgressCallback? onReceiveProgress,
  }) {
    return _execute<T>(
      ApiRequest(
        method: method,
        uri: buildUri(path, query),
        headers: buildHeaders(headers, body: body),
        body: body,
        responseType: responseType,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      ),
      parser,
    );
  }

  /// Releases the underlying connection pool.
  void close();

  // ---------- For subclasses ----------

  /// Performs the network call. Return the response for any status code;
  /// throw [ApiException] for transport failures (network, timeout, cancel).
  @protected
  Future<ApiResponse> send(ApiRequest request);

  /// Called after [updateConfig].
  @protected
  void onConfigChanged() {}

  /// Joins [path] onto the base URL. Absolute URLs are used as given.
  @protected
  Uri buildUri(String path, Map<String, dynamic>? query) {
    final isAbsolute =
        path.startsWith('http://') || path.startsWith('https://');
    final base = _config.baseUrl.endsWith('/')
        ? _config.baseUrl.substring(0, _config.baseUrl.length - 1)
        : _config.baseUrl;
    final relative = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse(
        isAbsolute ? path : (relative.isEmpty ? base : '$base/$relative'));

    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParametersAll,
      for (final e in query.entries)
        if (e.value != null)
          e.key: e.value is Iterable
              ? (e.value as Iterable).map((v) => '$v').toList()
              : '${e.value}',
    });
  }

  /// Default headers + auth header + per-request headers (highest priority).
  ///
  /// For file bodies the default JSON `Content-Type` is replaced: multipart
  /// bodies get theirs (with boundary) from the transport, raw files use the
  /// file's MIME type.
  @protected
  Map<String, String> buildHeaders(Map<String, String>? extra,
      {Object? body}) {
    final headers = <String, String>{};
    _config.headers.forEach((k, v) => _setHeader(headers, k, v));

    if (body is ApiFormData) {
      headers.removeWhere((k, _) => k.toLowerCase() == 'content-type');
    } else if (body is ApiFile) {
      _setHeader(headers, 'Content-Type', body.contentType);
    } else if (body is List<int>) {
      _setHeader(headers, 'Content-Type', 'application/octet-stream');
    }

    final token = _authToken;
    if (token != null && token.isNotEmpty) {
      _setHeader(headers, _config.authHeaderKey,
          '${_config.authScheme} $token'.trim());
    }
    extra?.forEach((k, v) => _setHeader(headers, k, v));
    return headers;
  }

  // ---------- Internals ----------

  Future<T> _execute<T>(ApiRequest request, JsonParser<T>? parser) async {
    final stopwatch = Stopwatch()..start();
    _logger.logRequest(
        request.method, request.uri, request.headers, request.body);

    final ApiResponse response;
    try {
      response = await send(request);
    } catch (e, st) {
      throw _fail(
        request,
        stopwatch,
        e is ApiException
            ? e
            : ApiException(
                type: ApiErrorType.unknown,
                message: e is UnsupportedError ? '${e.message}' : '$e',
                error: e,
                stackTrace: st,
              ),
      );
    }

    if (!response.isSuccess) {
      throw _fail(
          request,
          stopwatch,
          ApiException.fromResponse(
              response.statusCode, _decodeErrorBody(response.data)));
    }

    _logger.logResponse(request.method, request.uri, response.statusCode,
        response.data, stopwatch.elapsed);

    try {
      return parser != null ? parser(response.data) : response.data as T;
    } catch (e, st) {
      throw _fail(
        request,
        stopwatch,
        ApiException(
          type: ApiErrorType.parse,
          message: 'Failed to parse response: $e',
          statusCode: response.statusCode,
          data: response.data,
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  ApiException _fail(ApiRequest request, Stopwatch stopwatch, ApiException e) {
    _logger.logError(request.method, request.uri, e, stopwatch.elapsed);
    return e;
  }

  /// Error bodies of byte requests arrive as bytes; decode them so the
  /// server's error message can be read.
  static dynamic _decodeErrorBody(dynamic data) {
    if (data is! Uint8List) return data;
    if (data.isEmpty) return null;
    final text = utf8.decode(data, allowMalformed: true);
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  /// Sets a header, replacing any existing key that differs only in case.
  static void _setHeader(Map<String, String> headers, String key, String value) {
    headers.removeWhere((k, _) => k.toLowerCase() == key.toLowerCase());
    headers[key] = value;
  }

  static ApiLogger _createLogger(ApiConfig config) => ApiLogger(
        enabled: config.enableLogging,
        maxLength: config.maxLogLength,
        redactedHeaders: {'authorization', config.authHeaderKey},
      );
}
