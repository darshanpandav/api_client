import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'api_file.dart';

/// [ApiClient] backed by `package:dio`.
///
/// The underlying [dio] instance is public, so you can add your own
/// interceptors (e.g. token refresh), or use any other Dio feature directly.
class DioApiClient extends ApiClient {
  DioApiClient(super.config, {Dio? dio}) : dio = dio ?? Dio() {
    _applyOptions();
  }

  final Dio dio;

  static const _responseTypes = {
    ApiResponseType.json: ResponseType.json,
    ApiResponseType.text: ResponseType.plain,
    ApiResponseType.bytes: ResponseType.bytes,
  };

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    try {
      final (data, contentLength) = await _toDioData(request.body);
      final options = Options(
        method: request.method.value,
        headers: {
          ...request.headers,
          if (contentLength != null) Headers.contentLengthHeader: '$contentLength',
        },
        // Dio warns if sendTimeout is set on a request without a body.
        sendTimeout: data != null ? config.sendTimeout : null,
        responseType: _responseTypes[request.responseType],
        // Status codes are checked in ApiClient, so accept them all here.
        // Downloads only accept 2xx, so an error page is never saved to disk.
        validateStatus: request.savePath == null
            ? (_) => true
            : (status) => status != null && status >= 200 && status < 300,
      );

      final savePath = request.savePath;
      if (savePath != null) {
        final response = await dio.downloadUri(
          request.uri,
          savePath,
          options: options,
          onReceiveProgress: request.onReceiveProgress,
        );
        return ApiResponse(
          statusCode: response.statusCode ?? 0,
          data: savePath,
          headers: _headers(response),
        );
      }

      final response = await dio.requestUri<dynamic>(
        request.uri,
        data: data,
        options: options,
        onSendProgress: request.onSendProgress,
        onReceiveProgress: request.onReceiveProgress,
      );
      return ApiResponse(
        statusCode: response.statusCode ?? 0,
        data: _normalize(response.data, request.responseType),
        headers: _headers(response),
      );
    } on DioException catch (e, st) {
      throw _mapDioException(e, st);
    }
  }

  @override
  void onConfigChanged() => _applyOptions();

  @override
  void close() => dio.close();

  void _applyOptions() {
    dio.options
      ..baseUrl = config.baseUrl
      ..connectTimeout = config.connectTimeout
      ..receiveTimeout = config.receiveTimeout;
  }

  /// Converts our body types into what Dio expects.
  /// Returns the data and, for streams, its length.
  Future<(Object?, int?)> _toDioData(Object? body) async {
    if (body is ApiFormData) {
      final form = FormData()..fields.addAll(body.fields);
      for (final file in body.files) {
        form.files.add(MapEntry(file.key, await _toMultipartFile(file.value)));
      }
      return (form, null);
    }
    if (body is ApiFile) {
      final file = await _toMultipartFile(body);
      return (file.finalize(), file.length);
    }
    // Dio sends only Uint8List as raw bytes; other List<int>s would be
    // JSON-encoded.
    if (body is List<int> && body is! Uint8List) {
      return (Uint8List.fromList(body), null);
    }
    return (body, null);
  }

  Future<MultipartFile> _toMultipartFile(ApiFile file) {
    final contentType = DioMediaType.parse(file.contentType);
    final bytes = file.bytes;
    if (bytes != null) {
      return Future.value(MultipartFile.fromBytes(bytes,
          filename: file.filename, contentType: contentType));
    }
    return MultipartFile.fromFile(file.path!,
        filename: file.filename, contentType: contentType);
  }

  /// Makes Dio's output match [HttpApiClient] for the same response type.
  dynamic _normalize(dynamic data, ApiResponseType type) {
    if (type == ApiResponseType.bytes && data is List<int> && data is! Uint8List) {
      return Uint8List.fromList(data);
    }
    if (type == ApiResponseType.json && data is String && data.isEmpty) {
      return null;
    }
    return data;
  }

  Map<String, String> _headers(Response<dynamic> response) => response
      .headers.map
      .map((key, values) => MapEntry(key, values.join(', ')));

  ApiException _mapDioException(DioException e, StackTrace st) {
    final response = e.response;
    if (e.type == DioExceptionType.badResponse && response != null) {
      return ApiException.fromResponse(response.statusCode ?? 0, response.data);
    }

    final (type, message) = switch (e.type) {
      DioExceptionType.connectionTimeout => (
          ApiErrorType.timeout,
          'Connection timed out after ${config.connectTimeout.inSeconds}s'
        ),
      DioExceptionType.sendTimeout => (
          ApiErrorType.timeout,
          'Sending the request timed out'
        ),
      DioExceptionType.receiveTimeout => (
          ApiErrorType.timeout,
          'Receiving the response timed out'
        ),
      DioExceptionType.cancel => (
          ApiErrorType.cancelled,
          'Request was cancelled'
        ),
      DioExceptionType.connectionError => (
          ApiErrorType.network,
          'No internet connection or the server could not be reached'
        ),
      DioExceptionType.badCertificate => (
          ApiErrorType.network,
          'Bad SSL certificate'
        ),
      _ => (ApiErrorType.unknown, e.message ?? e.error?.toString() ?? '$e'),
    };

    return ApiException(
      type: type,
      message: message,
      error: e,
      stackTrace: st,
    );
  }
}
