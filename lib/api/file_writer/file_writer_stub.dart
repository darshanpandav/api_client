/// Web fallback: there is no file system to save to.
Future<void> writeStreamToFile(Stream<List<int>> stream, String path) {
  throw UnsupportedError(
      'Saving downloads to a file path is not supported on this platform. '
      'Use get(..., responseType: ApiResponseType.bytes) instead.');
}
