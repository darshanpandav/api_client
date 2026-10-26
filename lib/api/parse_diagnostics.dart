import 'dart:collection';

/// Where and why a response parser failed. Built only in debug mode.
///
/// Every value comes from runtime information: the source location from the
/// parser's stack trace, the field from re-running the parser on a copy of
/// the response that records which JSON keys are read, and the types from
/// the error message. Values that cannot be determined are left null.
class ParseErrorDetails {
  const ParseErrorDetails({
    required this.error,
    required this.stackTrace,
    this.file,
    this.line,
    this.column,
    this.member,
    this.jsonPath,
    this.fieldValueType,
    this.fieldConfirmed = false,
    this.expectedType,
    this.actualType,
  });

  final Object error;
  final StackTrace stackTrace;

  /// Source file of the most relevant stack frame, e.g.
  /// `package:demo/Product_model.dart`.
  final String? file;
  final int? line;
  final int? column;

  /// Function at that location, e.g. `Products.fromJson`.
  final String? member;

  /// Path of the last JSON value the parser read before failing,
  /// e.g. `products[0].price`.
  final String? jsonPath;

  /// Runtime type of the value at [jsonPath].
  final String? fieldValueType;

  /// True when the value at [jsonPath] has exactly the type the error
  /// reports as received, so it is the value that failed.
  final bool fieldConfirmed;

  /// From the error message: `type 'int' is not a subtype of type 'double?'`.
  final String? expectedType;
  final String? actualType;

  bool get hasLocation => file != null && line != null;

  /// Last segment of [jsonPath]: `price` for `products[0].price`.
  String? get field {
    final path = jsonPath;
    if (path == null) return null;
    final match = RegExp(r'([^.\[\]]+)\]?$').firstMatch(path);
    return match?.group(1);
  }

  String get fileName => file?.split('/').last ?? '';

  String get location {
    if (!hasLocation) return 'unknown location';
    final where = '$fileName:$line';
    return member == null ? where : '$where ($member)';
  }

  /// One actionable sentence for [ApiException.message].
  String get message {
    final buffer = StringBuffer();
    final isTypeMismatch = expectedType != null && actualType != null;
    buffer.write(isTypeMismatch ? 'Type mismatch' : 'Failed to parse response');
    buffer.write(hasLocation
        ? ' in $location'
        : ' (source location not found, see the stack trace)');

    final path = jsonPath;
    if (path != null && fieldConfirmed) {
      buffer.write(' — field "$field"');
      if (path != field) buffer.write(' (JSON path: $path)');
    } else if (path != null) {
      buffer.write(' — last JSON field read: "$path"'
          '${fieldValueType == null ? '' : ' ($fieldValueType)'}');
    }

    if (isTypeMismatch) {
      buffer.write(fieldConfirmed || path == null ? ' ' : ', ');
      buffer.write('expected $expectedType, but received $actualType. '
          'Check the model field and JSON parsing logic.');
    } else {
      buffer.write(': ${_firstLine(error)}');
    }
    return buffer.toString();
  }

  /// Builds the details for a parser that threw [error].
  ///
  /// [rerun] re-invokes the parser with the given data; it is called once
  /// with a recording copy of [data] to find the field being read.
  static ParseErrorDetails analyze({
    required Object error,
    required StackTrace stackTrace,
    required dynamic data,
    void Function(dynamic data)? rerun,
  }) {
    final frame = _relevantFrame(stackTrace);
    final types = _parseTypes('$error');

    String? jsonPath;
    String? valueType;
    var confirmed = false;
    if (rerun != null && (data is Map || data is List)) {
      final recorder = _JsonAccessRecorder();
      try {
        rerun(recorder.wrap(_deepCopy(data), ''));
      } catch (e, st) {
        // Trust the recording only if the re-run failed the same way, at the
        // same place. (The message can differ: the recorder's Map/List
        // wrappers have their own type names.)
        final sameFailure = e.runtimeType == error.runtimeType &&
            _parseTypes('$e')?.$1 == types?.$1 &&
            _relevantFrame(st)?.sameLocation(frame) == true;
        if (sameFailure && recorder.lastPath != null) {
          jsonPath = recorder.lastPath;
          valueType = _typeName(recorder.lastValue);
          confirmed =
              types != null && _hasType(recorder.lastValue, types.$2);
        }
      }
    }

    return ParseErrorDetails(
      error: error,
      stackTrace: stackTrace,
      file: frame?.uri,
      line: frame?.line,
      column: frame?.column,
      member: frame?.member,
      jsonPath: jsonPath,
      fieldValueType: valueType,
      fieldConfirmed: confirmed,
      expectedType: types?.$1,
      actualType: types?.$2,
    );
  }

  static String _firstLine(Object error) => '$error'.split('\n').first;

  static String _typeName(Object? value) => switch (value) {
        null => 'Null',
        Map() => 'Map',
        List() => 'List',
        _ => '${value.runtimeType}',
      };

  /// Whether [value] is what the error message reported as received.
  static bool _hasType(Object? value, String actualType) => switch (value) {
        null => actualType == 'Null',
        Map() => actualType.contains('Map'),
        List() => actualType.contains('List'),
        _ => '${value.runtimeType}' == actualType,
      };

  /// (expected, actual) from the VM, dart2js and DDC type error messages.
  static (String, String)? _parseTypes(String message) {
    final vm = RegExp(r"type '(.+?)' is not a subtype of type '(.+?)'")
        .firstMatch(message);
    if (vm != null) return (vm.group(2)!, _jsTypeName(vm.group(1)!));
    final ddc = RegExp(r"Expected a value of type '(.+?)', "
            r"but got one of type '(.+?)'")
        .firstMatch(message);
    if (ddc != null) return (ddc.group(1)!, _jsTypeName(ddc.group(2)!));
    return null;
  }

  /// dart2js reports JS-backed types (`JSInt`); show the Dart name.
  static String _jsTypeName(String type) => switch (type) {
        'JSInt' || 'JSPositiveInt' || 'JSUInt31' || 'JSUInt32' => 'int',
        'JSNumNotInt' => 'double',
        'JSString' => 'String',
        'JSBool' => 'bool',
        _ => type,
      };

  // ---------- Stack trace ----------

  /// The first frame outside the Dart/Flutter SDK, third-party HTTP packages
  /// and this API folder: normally the model line that threw.
  static _Frame? _relevantFrame(StackTrace stackTrace) {
    final frames = '$stackTrace'
        .split('\n')
        .map(_Frame.parse)
        .whereType<_Frame>()
        .toList();
    final apiDir = _apiDirectory();
    bool isOwnCode(_Frame f) =>
        !f.uri.startsWith('dart:') &&
        !_ignoredPackages.any((p) => f.uri.startsWith('package:$p/')) &&
        (apiDir == null || !f.uri.startsWith(apiDir));

    // Prefer frames from the app's own package, then any other package.
    final appPackage = apiDir == null ? null : _packagePrefix(apiDir);
    final own = frames.where(isOwnCode);
    return own.where((f) => appPackage != null && f.uri.startsWith(appPackage))
            .firstOrNull ??
        own.firstOrNull;
  }

  static const _ignoredPackages = {
    'flutter',
    'dio',
    'http',
    'http_parser',
    'async',
    'stack_trace',
  };

  /// URI of the folder holding this file (e.g. `package:demo/api/`),
  /// read from a live stack trace so the folder can be renamed or moved.
  static String? _apiDirectory() {
    if (_cachedApiDir != null) return _cachedApiDir;
    final here = '${StackTrace.current}'
        .split('\n')
        .map(_Frame.parse)
        .whereType<_Frame>()
        .firstOrNull;
    if (here == null) return null;
    final slash = here.uri.lastIndexOf('/');
    if (slash < 0) return null;
    return _cachedApiDir = here.uri.substring(0, slash + 1);
  }

  static String? _cachedApiDir;

  static String? _packagePrefix(String uri) {
    final match = RegExp(r'^package:[^/]+/').firstMatch(uri);
    return match?.group(0);
  }

  // ---------- JSON copy ----------

  static dynamic _deepCopy(dynamic value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final e in value.entries) '${e.key}': _deepCopy(e.value),
      };
    }
    if (value is List) return <dynamic>[for (final v in value) _deepCopy(v)];
    return value;
  }

  @override
  String toString() => message;
}

/// One stack frame from a VM or Flutter web (DDC) stack trace.
class _Frame {
  const _Frame(this.uri, this.line, this.column, this.member);

  final String uri;
  final int line;
  final int? column;
  final String? member;

  bool sameLocation(_Frame? other) =>
      other != null &&
      uri == other.uri &&
      line == other.line &&
      column == other.column;

  // VM:  #0      new Products.fromJson (package:demo/Product_model.dart:86:13)
  static final _vm = RegExp(r'^#\d+\s+(.+?) \((.+?):(\d+)(?::(\d+))?\)$');

  // Web: packages/demo/Product_model.dart 86:13   new Products.fromJson
  static final _web = RegExp(r'^(\S+\.dart) (\d+)(?::(\d+))?\s+(.+)$');

  static _Frame? parse(String raw) {
    final text = raw.trim();
    final vm = _vm.firstMatch(text);
    if (vm != null) {
      return _Frame(vm.group(2)!, int.parse(vm.group(3)!),
          int.tryParse(vm.group(4) ?? ''), _cleanMember(vm.group(1)!));
    }
    final web = _web.firstMatch(text);
    if (web != null) {
      var uri = web.group(1)!;
      if (uri.startsWith('packages/')) {
        uri = 'package:${uri.substring('packages/'.length)}';
      }
      return _Frame(uri, int.parse(web.group(2)!),
          int.tryParse(web.group(3) ?? ''), _cleanMember(web.group(4)!));
    }
    return null;
  }

  /// `new Products.fromJson` -> `Products.fromJson`,
  /// `ObjectService.getProduct.<anonymous closure>` -> `ObjectService.getProduct`.
  static String _cleanMember(String member) => member
      .replaceFirst(RegExp(r'^new '), '')
      .replaceAll('.<anonymous closure>', '')
      .replaceAll('.<fn>', '');
}

/// Wraps decoded JSON so every key or index the parser reads is recorded.
/// Used only on a throwaway copy while diagnosing a failed parse.
class _JsonAccessRecorder {
  String? lastPath;
  Object? lastValue;

  dynamic wrap(dynamic value, String path) {
    if (value is Map<String, dynamic>) return _RecordingMap(value, path, this);
    if (value is List) return _RecordingList(value, path, this);
    return value;
  }

  dynamic read(dynamic value, String path) {
    lastPath = path;
    lastValue = value;
    return wrap(value, path);
  }
}

class _RecordingMap extends MapBase<String, dynamic> {
  _RecordingMap(this._source, this._path, this._recorder);

  final Map<String, dynamic> _source;
  final String _path;
  final _JsonAccessRecorder _recorder;

  @override
  dynamic operator [](Object? key) => _recorder.read(
      _source[key], _path.isEmpty ? '$key' : '$_path.$key');

  @override
  void operator []=(String key, dynamic value) => _source[key] = value;

  @override
  Iterable<String> get keys => _source.keys;

  @override
  bool containsKey(Object? key) => _source.containsKey(key);

  @override
  dynamic remove(Object? key) => _source.remove(key);

  @override
  void clear() => _source.clear();
}

class _RecordingList extends ListBase<dynamic> {
  _RecordingList(this._source, this._path, this._recorder);

  final List<dynamic> _source;
  final String _path;
  final _JsonAccessRecorder _recorder;

  @override
  int get length => _source.length;

  @override
  set length(int value) => _source.length = value;

  @override
  dynamic operator [](int index) =>
      _recorder.read(_source[index], '$_path[$index]');

  @override
  void operator []=(int index, dynamic value) => _source[index] = value;

  @override
  void add(dynamic element) => _source.add(element);
}
