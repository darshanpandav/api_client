import 'dart:convert';

/// A file to upload, either from a path on disk or from bytes in memory.
///
/// Use it as a value in [ApiFormData] (multipart upload), or pass it directly
/// as `body` to send the raw bytes (e.g. a PUT to a pre-signed storage URL).
///
/// [ApiFile.fromPath] is not available on Flutter Web. Use [ApiFile.fromBytes]
/// there (e.g. with bytes from `image_picker`'s `XFile.readAsBytes()`).
class ApiFile {
  ApiFile.fromPath(String this.path, {String? filename, String? contentType})
      : bytes = null,
        filename = filename ?? _basename(path),
        contentType = contentType ?? contentTypeFor(filename ?? path);

  ApiFile.fromBytes(List<int> this.bytes,
      {required this.filename, String? contentType})
      : path = null,
        contentType = contentType ?? contentTypeFor(filename);

  final String? path;
  final List<int>? bytes;
  final String filename;

  /// MIME type, e.g. `image/jpeg`. Guessed from the file extension if omitted.
  final String contentType;

  @override
  String toString() {
    final source = bytes != null ? '${bytes!.length} bytes' : path;
    return '$filename ($contentType, $source)';
  }

  static String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

  /// Guesses a MIME type from a file name. Falls back to
  /// `application/octet-stream`.
  static String contentTypeFor(String filename) {
    final dot = filename.lastIndexOf('.');
    final ext = dot == -1 ? '' : filename.substring(dot + 1).toLowerCase();
    return _mimeTypes[ext] ?? 'application/octet-stream';
  }

  static const _mimeTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'svg': 'image/svg+xml',
    'ico': 'image/x-icon',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'pdf': 'application/pdf',
    'json': 'application/json',
    'zip': 'application/zip',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'html': 'text/html',
    'xml': 'application/xml',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };
}

/// A `multipart/form-data` body: text fields plus files.
///
/// ```dart
/// await api.post('/profile', body: ApiFormData.fromMap({
///   'name': 'Ana',
///   'avatar': ApiFile.fromPath(image.path),
///   'photos': [ApiFile.fromPath(a), ApiFile.fromPath(b)],
/// }));
/// ```
class ApiFormData {
  ApiFormData();

  /// Values may be an [ApiFile], a list of [ApiFile]s, or anything else.
  /// Maps and lists are sent as JSON strings, other values via `toString()`.
  /// Null values are skipped.
  factory ApiFormData.fromMap(Map<String, dynamic> map) {
    final form = ApiFormData();
    map.forEach((key, value) {
      if (value == null) return;
      if (value is ApiFile) {
        form.addFile(key, value);
      } else if (value is Iterable<ApiFile>) {
        for (final file in value) {
          form.addFile(key, file);
        }
      } else {
        form.addField(
            key,
            value is String
                ? value
                : (value is Map || value is Iterable)
                    ? jsonEncode(value)
                    : '$value');
      }
    });
    return form;
  }

  /// Note: [HttpApiClient] keeps only the last value if a field name repeats.
  /// Repeated file field names work on both clients.
  final List<MapEntry<String, String>> fields = [];
  final List<MapEntry<String, ApiFile>> files = [];

  void addField(String name, String value) => fields.add(MapEntry(name, value));

  void addFile(String name, ApiFile file) => files.add(MapEntry(name, file));
}
