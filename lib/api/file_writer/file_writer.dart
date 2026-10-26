// Picks the dart:io implementation on mobile/desktop and a stub on web.
export 'file_writer_stub.dart' if (dart.library.io) 'file_writer_io.dart';
