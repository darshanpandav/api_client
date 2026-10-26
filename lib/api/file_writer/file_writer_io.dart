import 'dart:io';

/// Streams [stream] into the file at [path], creating parent folders.
/// A partially written file is deleted if the stream fails.
Future<void> writeStreamToFile(Stream<List<int>> stream, String path) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final sink = file.openWrite();
  try {
    await sink.addStream(stream);
    await sink.close();
  } catch (_) {
    await sink.close().catchError((_) {});
    if (await file.exists()) await file.delete();
    rethrow;
  }
}
