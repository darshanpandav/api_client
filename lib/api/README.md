# API layer

A drop-in API folder for Flutter, with Dio and `http` behind one interface.

## Setup

1. Copy this `api/` folder into `lib/`.
2. Add the dependencies:
   ```yaml
   dependencies:
     dio: ^5.9.0
     http: ^1.6.0
     http_parser: ^4.1.2
   ```
3. Initialise it once in `main()`:
   ```dart
   import 'package:your_app/api/api.dart';

   void main() {
     ApiManager.init(
       const ApiConfig(baseUrl: 'https://api.example.com'),
       type: ApiClientType.dio, // or ApiClientType.http
     );
     runApp(const MyApp());
   }
   ```

## Usage

```dart
final api = ApiManager.client;

// Raw JSON
final json = await api.get('/users', query: {'page': 1});

// Typed result
final users = await api.get(
  '/users',
  parser: (json) => (json as List).map((e) => User.fromJson(e)).toList(),
  <!-- parser: (json) => LoginModel.fromJson(json as Map<String, dynamic>) -->
  <!-- parser: (json) => (json as List).map((e) => DetaModel.fromJson(e as Map<String, dynamic>).toList(), -->
);

// Maps and lists are sent as JSON
await api.post('/users', body: {'name': 'Ana'});

// Auth: the token is added to every request as `Authorization: Bearer <token>`
ApiManager.setAuthToken(token); // after login
ApiManager.setAuthToken(null);  // on logout

// Errors
try {
  await api.delete('/users/1');
} on ApiException catch (e) {
  if (e.type == ApiErrorType.unauthorized) { /* go to login */ }
  if (e.isNetworkError) { /* show offline message */ }
  print(e.message); // taken from the server's `message`/`error` field when present
}
```

## Files and other data types

| `body` value | Sent as |
| --- | --- |
| `Map` / `List` / other objects | JSON |
| `String` | Text, unchanged |
| `List<int>` / `Uint8List` | Raw bytes (`application/octet-stream`) |
| `ApiFile` | The file's raw bytes, with its MIME type (e.g. a PUT to a pre-signed storage URL) |
| `ApiFormData` | `multipart/form-data`: text fields plus files |

```dart
// Upload images and files with form fields, and track progress
await api.post(
  '/profile',
  body: ApiFormData.fromMap({
    'name': 'Ana',
    'avatar': ApiFile.fromPath(image.path),                   // mobile/desktop
    'cover': ApiFile.fromBytes(bytes, filename: 'cover.jpg'), // also works on web
    'photos': [ApiFile.fromPath(a), ApiFile.fromPath(b)],     // several files, one field
  }),
  onSendProgress: (sent, total) => print('${sent * 100 ~/ total}%'),
);

// Get an image or other binary file in memory
final Uint8List bytes = await api.get('/avatar.png', responseType: ApiResponseType.bytes);

// Stream a download straight to disk (not available on web)
await api.download('/report.pdf', '${dir.path}/report.pdf',
    onReceiveProgress: (received, total) { /* total is -1 if unknown */ });
```

The MIME type is guessed from the file extension. Pass `contentType:` to `ApiFile` to override it.
If a download fails, the partly written file is deleted.

## Config options (`ApiConfig`)

| Option | Default | Notes |
| --- | --- | --- |
| `baseUrl` | required | Request paths are appended to this. An absolute URL path skips it. |
| `headers` | JSON content type | Sent with every request. Can be overridden per request. |
| `connectTimeout` / `sendTimeout` | 30s | The `http` client waits up to connect + send + receive for the response headers. |
| `receiveTimeout` | 30s | Longest allowed gap between incoming chunks, so large downloads don't time out while data keeps arriving. |
| `authToken`, `authHeaderKey`, `authScheme` | `null`, `Authorization`, `Bearer` | Use `authScheme: ''` to send the raw token. |
| `enableLogging` | `kDebugMode` | Logs requests, responses and errors. The auth header is masked. |
| `maxLogLength` | 4000 | Longer logged bodies are truncated. |

To change settings at runtime, use `client.updateConfig(config.copyWith(...))`.

## Files

- `api.dart`: barrel export (import only this file)
- `api_manager.dart`: global init and access
- `api_client.dart`: shared interface. Handles URLs, headers, auth, logging, status checks and parsing.
- `dio_api_client.dart` / `http_api_client.dart`: the transport implementations
- `api_file.dart`: `ApiFile` and `ApiFormData` for uploads
- `file_writer/`: saves downloads to disk (with a web stub)
- `api_config.dart`, `api_exception.dart`, `api_logger.dart`

For other Dio features (interceptors, token refresh, cancel tokens), use
`(ApiManager.client as DioApiClient).dio`.
