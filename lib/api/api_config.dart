import 'package:flutter/foundation.dart';

/// All settings needed to talk to a backend.
///
/// Create one per backend and pass it to [ApiManager.init] (or directly to a
/// [DioApiClient] / [HttpApiClient]).
@immutable
class ApiConfig {
  const ApiConfig({
    required this.baseUrl,
    this.headers = const {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.authToken,
    this.authHeaderKey = 'Authorization',
    this.authScheme = 'Bearer',
    this.enableLogging = kDebugMode,
    this.maxLogLength = 4000,
  });

  /// e.g. `https://api.example.com/v1`. Request paths are appended to this.
  final String baseUrl;

  /// Default headers sent with every request.
  final Map<String, String> headers;

  /// Time allowed to establish the connection.
  final Duration connectTimeout;

  /// Longest allowed gap while receiving the response body, so large
  /// downloads don't time out as long as data keeps arriving.
  final Duration receiveTimeout;

  /// Time allowed to upload the request body.
  ///
  /// The `http` package has no per-phase timeouts, so [HttpApiClient] waits
  /// up to connect + send + receive timeouts for the response headers.
  final Duration sendTimeout;

  /// Initial auth token. Change it later with [ApiClient.setAuthToken].
  final String? authToken;

  /// Header that carries the token.
  final String authHeaderKey;

  /// Prefix before the token, e.g. `Bearer`. Use `''` to send the raw token.
  final String authScheme;

  /// Print requests, responses and errors to the console.
  /// Defaults to on in debug builds only.
  final bool enableLogging;

  /// Logged bodies longer than this are truncated.
  final int maxLogLength;

  ApiConfig copyWith({
    String? baseUrl,
    Map<String, String>? headers,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    String? authToken,
    String? authHeaderKey,
    String? authScheme,
    bool? enableLogging,
    int? maxLogLength,
  }) {
    return ApiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      headers: headers ?? this.headers,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      authToken: authToken ?? this.authToken,
      authHeaderKey: authHeaderKey ?? this.authHeaderKey,
      authScheme: authScheme ?? this.authScheme,
      enableLogging: enableLogging ?? this.enableLogging,
      maxLogLength: maxLogLength ?? this.maxLogLength,
    );
  }
}
