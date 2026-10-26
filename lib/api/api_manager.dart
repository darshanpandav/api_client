import 'api_client.dart';
import 'api_config.dart';
import 'dio_api_client.dart';
import 'http_api_client.dart';

enum ApiClientType { dio, http }

/// App-wide access point. Call [init] once in `main()`, then use
/// [ApiManager.client] anywhere.
///
/// ```dart
/// ApiManager.init(const ApiConfig(baseUrl: 'https://api.example.com'));
/// final users = await ApiManager.client.get('/users');
/// ```
class ApiManager {
  ApiManager._();

  static ApiClient? _client;

  /// Creates the shared client. Calling it again replaces (and closes) the
  /// previous one.
  static ApiClient init(
    ApiConfig config, {
    ApiClientType type = ApiClientType.dio,
  }) {
    _client?.close();
    return _client = switch (type) {
      ApiClientType.dio => DioApiClient(config),
      ApiClientType.http => HttpApiClient(config),
    };
  }

  static ApiClient get client {
    final client = _client;
    if (client == null) {
      throw StateError(
          'ApiManager.init(...) must be called before using ApiManager.client.');
    }
    return client;
  }

  static void setAuthToken(String? token) => client.setAuthToken(token);
}
