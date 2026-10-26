import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'api_file.dart';
import 'file_writer/file_writer.dart';

/// [ApiClient] backed by `package:http`.
class HttpApiClient extends ApiClient {
  HttpApiClient(super.config, {http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<ApiResponse> send(ApiRequest request) async {
    try {
      var httpRequest = await _buildRequest(request);
      final onSendProgress = request.onSendProgress;
      if (onSendProgress != null) {
        httpRequest = _withSendProgress(httpRequest, onSendProgress);
      }

      final response =
          await _client.send(httpRequest).timeout(_responseTimeout(request));

      // receiveTimeout = the longest allowed gap between incoming chunks.
      final body = _withReceiveProgress(
        response.stream.timeout(config.receiveTimeout),
        response.contentLength,
        request.onReceiveProgress,
      );

      final savePath = request.savePath;
      final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
      if (savePath != null && isSuccess) {
        await writeStreamToFile(body, savePath);
        return ApiResponse(
          statusCode: response.statusCode,
          data: savePath,
          headers: response.headers,
        );
      }

      final bytes = await http.ByteStream(body).toBytes();
      return ApiResponse(
        statusCode: response.statusCode,
        data: _decode(bytes, request.responseType),
        headers: response.headers,
      );
    } on TimeoutException catch (e, st) {
      throw ApiException(
        type: ApiErrorType.timeout,
        message: 'Request timed out after ${e.duration?.inSeconds}s',
        error: e,
        stackTrace: st,
      );
    } on http.ClientException catch (e, st) {
      throw ApiException(
        type: ApiErrorType.network,
        message: e.message,
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  void close() => _client.close();

  /// Time allowed until the response headers arrive.
  Duration _responseTimeout(ApiRequest request) =>
      config.connectTimeout +
      config.receiveTimeout +
      (request.body != null ? config.sendTimeout : Duration.zero);

  Future<http.BaseRequest> _buildRequest(ApiRequest request) async {
    final method = request.method.value;
    final body = request.body;

    if (body is ApiFormData) {
      // MultipartRequest sets its own Content-Type with the boundary.
      final multipart = http.MultipartRequest(method, request.uri)
        ..headers.addAll(request.headers);
      for (final field in body.fields) {
        multipart.fields[field.key] = field.value;
      }
      for (final file in body.files) {
        multipart.files.add(await _toMultipartFile(file.key, file.value));
      }
      return multipart;
    }

    final httpRequest = http.Request(method, request.uri)
      ..headers.addAll(request.headers);
    if (body == null) return httpRequest;

    if (body is String) {
      httpRequest.body = body;
    } else if (body is List<int>) {
      httpRequest.bodyBytes = body;
    } else if (body is ApiFile) {
      httpRequest.bodyBytes = await _readFile(body);
    } else {
      httpRequest.body = jsonEncode(body);
    }
    return httpRequest;
  }

  Future<http.MultipartFile> _toMultipartFile(String field, ApiFile file) {
    final contentType = MediaType.parse(file.contentType);
    final bytes = file.bytes;
    if (bytes != null) {
      return Future.value(http.MultipartFile.fromBytes(field, bytes,
          filename: file.filename, contentType: contentType));
    }
    return http.MultipartFile.fromPath(field, file.path!,
        filename: file.filename, contentType: contentType);
  }

  Future<List<int>> _readFile(ApiFile file) async {
    final bytes = file.bytes;
    if (bytes != null) return bytes;
    // Uses http's own platform-specific file reading.
    final multipartFile = await _toMultipartFile('file', file);
    return multipartFile.finalize().toBytes();
  }

  /// Re-sends [original] as a stream so upload progress can be reported.
  http.BaseRequest _withSendProgress(
      http.BaseRequest original, ApiProgressCallback onProgress) {
    final total = original.contentLength;
    final source = original.finalize();
    final streamed = http.StreamedRequest(original.method, original.url)
      ..headers.addAll(original.headers)
      ..contentLength = total;

    var sent = 0;
    source.listen(
      (chunk) {
        sent += chunk.length;
        onProgress(sent, total ?? -1);
        streamed.sink.add(chunk);
      },
      onError: streamed.sink.addError,
      onDone: streamed.sink.close,
      cancelOnError: true,
    );
    return streamed;
  }

  Stream<List<int>> _withReceiveProgress(
    Stream<List<int>> stream,
    int? total,
    ApiProgressCallback? onProgress,
  ) {
    if (onProgress == null) return stream;
    var received = 0;
    return stream.map((chunk) {
      received += chunk.length;
      onProgress(received, total ?? -1);
      return chunk;
    });
  }

  dynamic _decode(Uint8List bytes, ApiResponseType type) {
    switch (type) {
      case ApiResponseType.bytes:
        return bytes;
      case ApiResponseType.text:
        return utf8.decode(bytes, allowMalformed: true);
      case ApiResponseType.json:
        if (bytes.isEmpty) return null;
        final text = utf8.decode(bytes, allowMalformed: true);
        try {
          return jsonDecode(text);
        } on FormatException {
          return text;
        }
    }
  }
}
