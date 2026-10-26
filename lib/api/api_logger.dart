import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'api_file.dart';

/// Prints requests, responses and errors to the console.
/// Values of sensitive headers (such as the auth header) are masked.
class ApiLogger {
  ApiLogger({
    this.enabled = true,
    this.maxLength = 4000,
    Set<String> redactedHeaders = const {'authorization'},
  }) : _redactedHeaders = redactedHeaders.map((h) => h.toLowerCase()).toSet();

  final bool enabled;
  final int maxLength;
  final Set<String> _redactedHeaders;

  void logRequest(
    HttpMethod method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) {
    _print('REQUEST', [
      '${method.value} $uri',
      'Headers: ${_redact(headers)}',
      if (body != null) 'Body: ${_format(body)}',
    ]);
  }

  void logResponse(
    HttpMethod method,
    Uri uri,
    int statusCode,
    dynamic data,
    Duration elapsed,
  ) {
    _print('RESPONSE', [
      '${method.value} $uri',
      'Status: $statusCode (${elapsed.inMilliseconds} ms)',
      'Data: ${_format(data)}',
    ]);
  }

  void logError(
    HttpMethod method,
    Uri uri,
    ApiException exception,
    Duration elapsed,
  ) {
    _print('ERROR', [
      '${method.value} $uri',
      'Type: ${exception.type.name}'
          '${exception.statusCode == null ? '' : ' | Status: ${exception.statusCode}'}'
          ' (${elapsed.inMilliseconds} ms)',
      'Message: ${exception.message}',
      if (exception.data != null) 'Data: ${_format(exception.data)}',
      ..._parseDiagnostics(exception),
    ]);
  }

  /// Debug mode only (see [ApiException.parseDetails]).
  List<String> _parseDiagnostics(ApiException exception) {
    final details = exception.parseDetails;
    if (details == null) return const [];
    return [
      'Original error: ${details.error.runtimeType}: ${details.error}',
      if (details.hasLocation)
        'Source: ${details.file}:${details.line}'
            '${details.column == null ? '' : ':${details.column}'}'
            '${details.member == null ? '' : ' (${details.member})'}',
      if (details.jsonPath != null)
        'JSON path: ${details.jsonPath} (${details.fieldValueType})',
      // Full trace, untruncated, so nothing is hidden when the location
      // could not be pinned down.
      'Stack trace:\n${details.stackTrace}'.trimRight(),
    ];
  }

  void _print(String title, List<String> lines) {
    if (!enabled) return;
    debugPrint('┌─── API $title ───────────────────────────');
    for (final line in lines) {
      for (final part in line.split('\n')) {
        debugPrint('│ $part');
      }
    }
    debugPrint('└──────────────────────────────────────────');
  }

  Map<String, String> _redact(Map<String, String> headers) => {
        for (final e in headers.entries)
          e.key: _redactedHeaders.contains(e.key.toLowerCase()) ? '***' : e.value,
      };

  String _format(Object? data) {
    String text;
    if (data is ApiFormData) {
      text = [
        for (final f in data.fields) '${f.key}: ${f.value}',
        for (final f in data.files) '${f.key}: [file] ${f.value}',
      ].join('\n');
    } else if (data is ApiFile) {
      text = '[file] $data';
    } else if (data is List<int>) {
      // Raw bytes (uploads or ApiResponseType.bytes responses), not JSON.
      text = '<binary, ${data.length} bytes>';
    } else if (data is Map || data is List) {
      try {
        text = const JsonEncoder.withIndent('  ').convert(data);
      } catch (_) {
        text = data.toString();
      }
    } else {
      text = '$data';
    }
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}… (${text.length - maxLength} more chars)';
  }
}
